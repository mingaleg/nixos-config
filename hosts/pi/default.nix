{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = lib.optionals (builtins.pathExists ./hardware-configuration.nix) [
    ./hardware-configuration.nix
  ] ++ [
    ../../modules/pegasus-mount.nix
    ../../modules/network-tuning.nix
    ./pihole.nix
    ./nginx-www.nix
  ];

  # Agenix configuration
  age.identityPaths = [ "/root/.ssh/agenix-hosts" ];

  # Mount pegasus by IP: pi is itself the DNS server, and its
  # systemd-resolved setup doesn't reliably resolve local hostnames back
  # through its own pihole, so avoid that self-dependency here.
  pegasusMount.host = layout.machines.ronove.interfaces.eth.ip;

  networkTuning.interface = "end0";

  networking.hostName = "pi";
  
  nix.settings.trusted-users = [ "root" "mingaleg" ];

  # pi now gets its IP and DNS via DHCP from ronove (static reservation by
  # MAC keeps it pinned to layout.machines.pi.interfaces.eth.ip).

  services.openssh.enable = true;

  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
    hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";
  };

  environment.systemPackages = with pkgs; [
    vim git htop tmux ntfs3g
    ethtool iproute2 pciutils usbutils
    iperf3 curl wget bind speedtest-cli
  ];

  # Force CPU to performance governor
  powerManagement.cpuFreqGovernor = "performance";  
  # Alternatively, use ondemand but with better settings
  # powerManagement.cpuFreqGovernor = "ondemand";

  boot.loader.raspberry-pi.bootloader = "kernel";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
