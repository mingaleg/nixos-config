{ lib, modulesPath, ... }:

# Strip what nixos-raspberrypi's sd-image module drags in for a general-purpose
# installer image, for appliance-style Pis built as sd images (foreign-agent
# and its recovery stick, which carries a full copy of foreign-agent).

{
  # Installer/repair tools, plus btrfs/cifs(samba)/f2fs/ntfs/xfs/zfs support.
  # ZFS also matters for the build: its kernel module needs the kernel's -dev
  # output, i.e. a full rpi kernel build on builders that only have the kernel.
  disabledModules = [ (modulesPath + "/profiles/base.nix") ];
  boot.supportedFilesystems = lib.mkForce { ext4 = true; vfat = true; };

  # Firmware for every device ever made (~740MiB of linux-firmware). Hosts
  # that need Wi-Fi add just the Pi's blob back.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # Remote deploys don't need nixpkgs' source on the target.
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;

  documentation.enable = false;

  # nixos-rebuild & co. (and the ~110MiB python they need). Deploys run
  # `nixos-rebuild --target-host` from another machine; the target only needs
  # nix and its own switch-to-configuration.
  system.disableInstallerTools = true;
}
