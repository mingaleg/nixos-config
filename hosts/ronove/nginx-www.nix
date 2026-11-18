{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;

  pegasusWww = {
    root = "/mnt/pegasus/www";
    extraConfig = ''
      autoindex on;
    '';
  };
in
{
  services.nginx = {
    enable = true;

    virtualHosts."ronove" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 6278;
        }
      ];

      locations."/" = pegasusWww;
    };

    # Same share on port 80 under its own name; :6278 stays for old links.
    # The name resolves via pihole.wildcardMachines (see pihole.nix).
    virtualHosts."pegasus.ronove" = {
      serverAliases = [ "pegasus.ronove.${layout.domain}" ];
      locations."/" = pegasusWww;
    };
  };

  # Open port 6278 in the firewall
  networking.firewall.allowedTCPPorts = [ 6278 ];
}
