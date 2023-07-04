{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    coreutils-full
    killall

    gh
    git

    htop

    nixpkgs-fmt

    tmux
    vim

    wget
  ];
}
