{ config, pkgs, lib, ... }:

# Ex-pi Raspberry Pi 5, living at Igor and Tanya's house as a foothold into
# their network. Reachable only over the VPN (it dials out to vps) - see
# foreign-agent.md. Filesystems come from nixos-raspberrypi's sd-image module
# (added in flake.nix), so the same config also builds the image that the
# recovery stick (hosts/foreign-agent-recovery) flashes back onto the SD card.

{
  imports = [
    ../../modules/core-server
    ../../modules/hosts-file.nix
    ./network.nix
    ./wireguard.nix
    ./recovery.nix
  ];

  networking.hostName = "foreign-agent";

  # Own host key as agenix identity instead of the fleet-wide agenix-hosts key:
  # the recovery stick carries this key, and a lost stick must not expose
  # every other host's secrets. See secrets/secrets.nix.
  age.identityPaths = lib.mkForce [ "/etc/ssh/ssh_host_ed25519_key" ];
  # Only the key the recovery stick restores, so a reinstall never presents a
  # freshly generated (RSA) host key.
  services.openssh.hostKeys = [
    { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
  ];

  users.users.mingaleg.hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";

  environment.systemPackages = with pkgs; [
    vim git htop tmux ntfs3g
    ethtool iproute2 pciutils usbutils
    iperf3 curl wget bind speedtest-cli
    wireguard-tools raspberrypi-eeprom
  ];

  # Nobody on site can press a reset button for us: let the hardware watchdog
  # reboot the box if the kernel/systemd hangs.
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  # Force CPU to performance governor
  powerManagement.cpuFreqGovernor = "performance";

  system.stateVersion = "25.11";
}
