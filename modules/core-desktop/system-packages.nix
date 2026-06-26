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

    btop
    tldr
    tree
    tmux
    vim
    wget
    bat

    # Network
    cifs-utils  # SMB/CIFS mounting
    samba       # SMB client tools (smbclient)
    wireguard-tools

    # VoIP
    mumble

    acpi
    perl

    picom
    dunst
    libnotify

    gnumake
    gcc

    texlive.combined.scheme-full
    imagemagick
  ];
}
