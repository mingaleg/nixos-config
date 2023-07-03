{ config, pkgs, nix-vscode-extensions, ... }:

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
    userName = "Oleg Mingalev";
    userEmail = "oleg@mingalev.net";
  };

  # Packages that should be installed to the user profile.
  home.packages = [ ];

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
    };
  };

  home.stateVersion = "23.05";

  programs.home-manager.enable = true;
}
