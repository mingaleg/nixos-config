{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    gh
    git
    htop
    tmux
    vim
    wget
  ];
}

