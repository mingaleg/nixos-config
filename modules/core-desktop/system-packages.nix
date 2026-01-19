{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    coreutils-full
    killall
    lsof

    gh
    git

    python3

    nixpkgs-fmt

    htop
    tldr
    tree
    tmux
    vim
    wget

    # i3blocks dependencies
    acpi
    perl
  ];
}
