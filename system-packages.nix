{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gh
    git
    htop
    nixpkgs-fmt
    tmux
    vim
    wget
  ];
}

