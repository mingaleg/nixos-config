{ config, pkgs, nix-vscode-extensions, ... }:

let
  layout = import ./home-network/layout.nix;
in
{
  home.username = "mingaleg";
  home.homeDirectory = "/home/mingaleg";

  # set cursor size and dpi for 4k monitor
  xresources.properties = {
    "Xcursor.size" = 16;
    "Xft.dpi" = 172;
  };

  # basic configuration of git, please change to your own
  programs.git = {
    enable = true;
    settings = {
      user.name = "Oleg Mingalev";
      user.email = "oleg@mingalev.net";
    };
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = "Oleg Mingalev";
        email = "oleg@mingalev.net";
      };
    };
  };

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    rofi
    claude-code
    alacritty
    feh
    vlc
    wireshark
    telegram-desktop
    slack
    google-cloud-sdk
    qrencode
    transmission_4-gtk
  ];

  # starship - a customizable prompt for any shell
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      aws.disabled = true;
      gcloud.disabled = true;
      shlvl.disabled = true;

      directory = {
        truncation_length = 6;
      };
    };
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
    '';
  };

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

  home.sessionVariables = {
    EDITOR = "vim";
    TERMINAL = "alacritty";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "home-canonicalize" = {
        host = "* !*.* !localhost";
        extraOptions = {
          CanonicalDomains = layout.domain;
          CanonicalizeHostname = "yes";
          CanonicalizeFallbackLocal = "no";
        };
      };
      "home-identity" = {
        host = "*.${layout.domain}";
        identityFile = "~/.ssh/mingaleg-masterkey";
        identitiesOnly = true;
      };
      "home-gw" = {
        hostname = "home-gw.mingalev.net";
        identityFile = "~/.ssh/mingaleg-masterkey";
        identitiesOnly = true;
      };
    };
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
  };

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
