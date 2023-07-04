{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    coreutils-full
    killall

    gh
    git

    nixpkgs-fmt

    htop
    tldr
    tmux
    vim
    wget
  ];
}
