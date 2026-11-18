{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core-server
    ../../modules/hosts-file.nix
    ../../modules/network-tuning.nix
    ./nginx-www.nix
    ./web-proxy.nix
    ./samba-server.nix
    ./pihole.nix
    ./wireguard-vpn.nix
    ./fleet-deployer.nix
    ./mingadocs.nix
  ];

  networking.hostName = "ronove";
  networkTuning.interface = "enp2s0";

  # Static IP now that ronove runs the DHCP/DNS server itself - can't depend
  # on DHCP (from itself or anything else) to get an address at boot.
  networking.useDHCP = false;
  networking.interfaces.enp2s0 = {
    ipv4.addresses = [{
      address = layout.machines.ronove.interfaces.eth.ip;
      prefixLength = layout.network.prefixLength;
    }];
  };
  networking.defaultGateway = layout.network.defaultGateway;
  networking.nameservers = [ "127.0.0.1" "1.1.1.1" ];  # Use itself for DNS

  boot.loader.grub.enable = true;
  # Stable by-id path, not /dev/sda: plain /dev/sdX shifts around based on USB
  # enumeration order - the HiLink modem's TF-card reader has claimed /dev/sda
  # before, bumping the real boot disk to /dev/sdb.
  boot.loader.grub.device = "/dev/disk/by-id/ata-WDC_WD3200LPLX-75ZNTT0_WXD1A65D9SF8";
  boot.loader.grub.useOSProber = true;

  # Pegasus NAS disk, physically moved over from `pi`
  fileSystems."/mnt/pegasus" = {
    device = "/dev/disk/by-uuid/0fd7125c-e77f-4a65-8e3d-984ecb96cadc";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    btop
    speedtest-cli
    tmux
    usb-modeswitch
    jq # reading fleet-deployer's API: curl -s localhost:8090/api/hosts | jq
  ];

  # HiLink cellular modem (Huawei E353/E3131) enumerates as a mass-storage
  # device (12d1:1f01) on cold-plug and needs usb_modeswitch to flip it into
  # modem/CDC-Ethernet mode before it presents a network interface (then
  # appears as enp0s20u10). The packaged udev rule dispatches to a templated
  # systemd service (usb_modeswitch@.service) whose compiled dispatcher binary
  # is broken in this nixpkgs build (errors on `--switch-mode` with "invalid
  # command name" from its Tcl usage parser) - confirmed by running it
  # manually. Bypassing it with our own udev rule that calls `usb_modeswitch`
  # directly, which works fine.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", ATTR{idProduct}=="1f01", RUN+="${pkgs.usb-modeswitch}/sbin/usb_modeswitch -v 0x12d1 -p 0x1f01 -c ${pkgs.usb-modeswitch-data}/share/usb_modeswitch/12d1:1f01"
  '';

  # HiLink modem interface - static IP to access modem API at 192.168.8.1.
  # No gateway set, so internet traffic stays on enp2s0.
  networking.interfaces.enp0s20u10 = {
    ipv4.addresses = [{
      address = "192.168.8.100";
      prefixLength = 24;
    }];
  };

  # Allow forwarding to the modem interface
  networking.firewall.trustedInterfaces = [ "enp0s20u10" ];

  # NAT for modem access - masquerade traffic going to the modem (from both
  # LAN clients via enp2s0 and VPN clients via wg0) so the modem sees
  # requests from ronove's IP (192.168.8.100) instead of the original
  # client IPs, which the modem has no route back to.
  networking.nat = {
    enable = true;
    externalInterface = "enp0s20u10";
    internalInterfaces = [ "enp2s0" "wg0" ];
  };

  # NTP server for the local network, moved over from pi.
  #
  # ronove's CMOS battery is dead: after a power cut the RTC comes back at
  # 2019-05-20, and until chrony steps the clock everything that starts early
  # (TLS downloads, Pi-hole's gravity run) sees 2019. So:
  #  - `-s` starts the clock from the drift file's mtime when that is later
  #    than the RTC, i.e. roughly when chronyd last ran, not 2019;
  #  - `activate 0.1` keeps the local reference off until we've synced to a
  #    real upstream at least once, so LAN clients are never handed our
  #    unsynced clock as stratum 10;
  #  - chrony-wait holds time-sync.target until the clock is synced, for
  #    units that care (see pihole-ftl-setup in modules/pihole.nix).
  services.chrony = {
    enable = true;
    servers = [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
    ];
    extraFlags = [ "-s" ];
    extraConfig = ''
      allow ${layout.network.prefix}.0/24
      local stratum 10 activate 0.1
    '';
  };
  networking.firewall.allowedUDPPorts = [ 123 ];

  # Same as upstream chrony's chrony-wait.service. Bounded, so with no internet
  # it gives up after ~3 minutes and lets time-sync.target through anyway.
  systemd.services.chrony-wait = {
    description = "Wait for chrony to synchronize system clock";
    after = [ "chronyd.service" ];
    requires = [ "chronyd.service" ];
    before = [ "time-sync.target" ];
    wantedBy = [ "time-sync.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      DynamicUser = true;
      ExecStart = "${pkgs.chrony}/bin/chronyc -h 127.0.0.1,::1 waitsync 180 0.1 0.0 1";
    };
  };

  system.stateVersion = "25.11";
}
