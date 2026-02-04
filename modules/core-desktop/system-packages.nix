{ pkgs, agenix, ... }:

{
  environment.systemPackages = with pkgs; [
    coreutils-full
    killall
    lsof
    pciutils

    gh
    git
    agenix.packages.${pkgs.system}.default

    python3

    nixpkgs-fmt

    htop
    tldr
    tree
    tmux
    vim
    wget

    # Network
    cifs-utils  # SMB/CIFS mounting
    samba       # SMB client tools (smbclient)

    acpi
    perl

    picom

    gnumake

    texlive.combined.scheme-full
    imagemagick
  ];
}
