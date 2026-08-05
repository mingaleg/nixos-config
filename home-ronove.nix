{ config, pkgs, lib, ... }:

{
  imports = [ ./home-server.nix ];

  programs.ssh.matchBlocks."github" = {
    host = "github.com";
    identityFile = "~/.ssh/mingaleg-masterkey";
  };
}
