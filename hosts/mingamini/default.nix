# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./wireguard.nix
      ../../modules/core-desktop
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "mingamini";

  # Enable Intel graphics drivers and hardware acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver  # LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver  # LIBVA_DRIVER_NAME=i965 (older but sometimes better)
      libva-vdpau-driver
      libvdpau-va-gl
      intel-compute-runtime # OpenCL support
    ];
  };

  # Use Intel driver with TearFree option
  services.xserver.videoDrivers = [ "intel" ];

  # Enable TearFree to prevent screen tearing at X server level
  services.xserver.deviceSection = ''
    Option "TearFree" "true"
    Option "DRI" "3"
  '';

  # Enable wifi support with iwd (provides iwctl)
  networking.wireless.iwd.enable = true;

  # Rotate display to the right at X server level
  services.xserver.xrandrHeads = [
    {
      output = "DSI1";
      primary = true;
      monitorConfig = ''
        Option "Rotate" "right"
      '';
    }
  ];

  # Rotate touchscreen to match display rotation and configure touchpad scrolling
  services.xserver.displayManager.sessionCommands = ''
    # Rotate touchscreen to match display rotation
    ${pkgs.xorg.xinput}/bin/xinput set-prop "GXTP7380:00 27C6:0113" "Coordinate Transformation Matrix" 0 1 0 -1 0 1 0 0 1

    # Enable button scrolling on HAILUCK touchpad (middle button)
    ${pkgs.xorg.xinput}/bin/xinput set-prop "HAILUCK CO.,LTD USB KEYBOARD Mouse" "libinput Scroll Method Enabled" 0 0 1
    ${pkgs.xorg.xinput}/bin/xinput set-prop "HAILUCK CO.,LTD USB KEYBOARD Mouse" "libinput Button Scrolling Button" 2
    ${pkgs.xorg.xinput}/bin/xinput set-prop "HAILUCK CO.,LTD USB KEYBOARD Mouse" "libinput Middle Emulation Enabled" 0
  '';

  # Enable sound with pipewire.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
