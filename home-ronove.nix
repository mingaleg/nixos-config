{ config, pkgs, lib, ... }:

{
  imports = [ ./home-server.nix ];

  programs.ssh.settings."github" = {
    header = "Host github.com";
    IdentityFile = "~/.ssh/mingaleg-masterkey";
  };
}
