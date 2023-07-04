# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, callPackage, nix-vscode-extensions, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./system-packages.nix
      ./vbox-guest.nix
    ];

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "minganix";

  # Set your time zone.
  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    useXkbConfig = true; # use xkbOptions in tty.
  };

  fonts.fonts = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts

    (nerdfonts.override { fonts = [ "DroidSansMono" ]; })
  ];

  services.xserver = {
    enable = true;
    layout = "us,ru";
    xkbOptions = "grp:caps_toggle";

    desktopManager = {
      xterm.enable = false;
      xfce = {
        enable = true;
        noDesktop = true;
        enableXfwm = false;
      };
    };

    displayManager.defaultSession = "none+i3";
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu
        i3status
        i3lock
        i3blocks
      ];
    };
  };

  sound.enable = true;
  hardware.pulseaudio.enable = true;

  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" "nixos" ];
    packages = with pkgs; [
      google-chrome
      tree
    ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ./ssh-keys/mingaleg-masterkey.pub)
    ];
  };

  users.groups.nixos = {
    gid = 42000;
  };

  environment = {
    pathsToLink = [ "/libexec" ];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Give `nixos` group write permission in /etc/nixos
  system.activationScripts.nixos-permissions = pkgs.lib.stringAfter [ "groups" ] ''
    chown -R root:nixos /etc/nixos
    find /etc/nixos -type d -exec chmod 0775 {} +
    find /etc/nixos -type d -exec chmod g+s  {} +
    find /etc/nixos -type f -exec chmod 0664 {} +
  '';

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # DISABLED: does not work with Nix Flakes
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}

