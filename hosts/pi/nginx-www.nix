{ config, pkgs, lib, ... }:

{
  services.nginx = {
    enable = true;

    virtualHosts."pi" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 6278;
        }
      ];

      locations."/" = {
        root = "/mnt/pegasus/www";
        extraConfig = ''
          autoindex on;
        '';
      };
    };
  };

  # Open port 6278 in the firewall
  networking.firewall.allowedTCPPorts = [ 6278 ];
}
