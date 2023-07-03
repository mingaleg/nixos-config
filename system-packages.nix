{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    coreutils-full
    gh
    git
    htop
    nixpkgs-fmt
    tmux
    vim
    wget
  ];
}

