{ config, pkgs, ... }:

let
  layout = import ./home-network/layout.nix;
in
{
  home.username = "mingaleg";
  home.homeDirectory = "/home/mingaleg";

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

  # CLI-only packages, safe on headless hosts too.
  home.packages = with pkgs; [
    claude-code
    google-cloud-sdk
    qrencode
    graphviz
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

  home.sessionVariables = {
    EDITOR = "vim";
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
        addressFamily = "inet";
      };
      "home-gw" = {
        hostname = "home-gw.mingalev.net";
        identityFile = "~/.ssh/mingaleg-masterkey";
        identitiesOnly = true;
      };
    };
  };

  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
