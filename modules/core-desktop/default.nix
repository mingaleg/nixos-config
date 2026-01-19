# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, callPackage, nix-vscode-extensions, ... }:

{
  imports =
    [
      ./system-packages.nix
    ];

  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    useXkbConfig = true; # use xkbOptions in tty.
  };

  fonts.packages = with pkgs; [
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
    xkb.layout = "us,ru";
    xkb.options = "grp:caps_toggle";

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

  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" "nixos" ];
    packages = with pkgs; [
      alacritty
      feh
      google-chrome
      vlc
    ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];

    # Generated with `mkpasswd -m sha-512`
    hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";
  };

  users.groups.nixos = {
    gid = 42000;
  };

  environment = {
    pathsToLink = [ "/libexec" ];
  };

  services.openssh.enable = true;


  # Give `nixos` group write permission in /etc/nixos
  system.activationScripts.nixos-permissions = pkgs.lib.stringAfter [ "groups" ] ''
    chown -R root:nixos /etc/nixos
    find /etc/nixos -type d -exec chmod 0775 {} +
    find /etc/nixos -type d -exec chmod g+s  {} +
    find /etc/nixos -type f -exec chmod 0664 {} +
  '';
}
