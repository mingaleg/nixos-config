{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    coreutils-full
    killall
    lsof

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
