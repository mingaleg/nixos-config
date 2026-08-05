{ config, pkgs, nix-vscode-extensions, ... }:

{
  imports = [ ./home-common.nix ];

  # set cursor size and dpi for 4k monitor
  xresources.properties = {
    "Xcursor.size" = 16;
    "Xft.dpi" = 172;
  };

  # Desktop/GUI-only packages.
  home.packages = with pkgs; [
    rofi
    alacritty
    feh
    vlc
    wireshark
    telegram-desktop
    slack
    transmission_4-gtk
    ghostty
  ];

  programs.vscode = {
    enable = true;

    profiles.default = {
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;

      extensions = (with pkgs.vscode-extensions; [
        bbenoist.nix
        jnoortheen.nix-ide

        ms-python.python

        github.vscode-pull-request-github
        ms-vscode-remote.remote-ssh
      ]) ++ (with nix-vscode-extensions.extensions.x86_64-linux.vscode-marketplace; [
        # For packages not available in https://search.nixos.org/packages?type=packages&query=vscode-extensions
      ]);

      userSettings = {
        "git.enableSmartCommit" = true;
        "git.confirmSync" = false;
        "git.autofetch" = true;
        "editor.fontFamily" = "'Droid Sans Mono', 'monospace', monospace, 'Noto Color Emoji'";
        "terminal.integrated.gpuAcceleration" = "off";
      };
    };
  };

  programs.opam = {
    enable = true;
  };

  home.sessionVariables = {
    TERMINAL = "ghostty";
  };

  # i3, i3blocks, rofi, and picom configuration managed via Nix
  home.file = {
    ".config/i3/config".source = ./etc/i3/config;
    ".config/i3blocks/config".source = ./etc/i3blocks/config;
    ".config/i3blocks/blocks" = {
      source = ./etc/i3blocks/blocks;
      recursive = true;
    };
    ".config/i3blocks/lib" = {
      source = ./etc/i3blocks/lib;
      recursive = true;
    };
    ".config/rofi" = {
      source = ./etc/rofi;
      recursive = true;
    };
    ".config/picom/picom.conf".source = ./etc/picom/picom.conf;
    ".config/ghostty/config.ghostty".text = ''
      theme = Broadcast
      window-decoration = none
    '';
  };
}
