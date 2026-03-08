{ config, pkgs, lib, ... }:

{
  # Create a launcher script that opens Mumble with the VPS server
  environment.systemPackages = [
    (pkgs.writeScriptBin "mumble-vps" ''
      #!${pkgs.bash}/bin/bash
      # Connect to Mumble server on VPS
      # Server: home-gw.mingalev.net:64738
      exec ${pkgs.mumble}/bin/mumble mumble://home-gw.mingalev.net:64738
    '')
  ];
}
