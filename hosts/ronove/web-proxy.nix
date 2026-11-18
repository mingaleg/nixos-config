{ config, lib, ... }:

# nginx owns port 80 on ronove and routes by name: fleet-deployer.ronove to the
# deployer, anything else (ronove, pi.hole, the bare IP) to the Pi-hole web
# interface, which pihole.webProxied moves to loopback. pegasus.ronove lives
# with the rest of the file share in nginx-www.nix.

let
  layout = import ../../home-network/layout.nix;

  # Not services.nginx.recommendedProxySettings: that sets X-Forwarded-For to
  # $proxy_add_x_forwarded_for, which keeps whatever the client sent.
  # fleet-deployer decides who may deploy by client address, and uvicorn takes
  # it from this header when the request comes from 127.0.0.1 (its default
  # forwarded_allow_ips) - so it must be exactly the peer nginx saw.
  proxyHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
  '';
in
{
  services.nginx = {
    enable = true;

    virtualHosts."fleet-deployer.ronove" = {
      serverAliases = [ "fleet-deployer.ronove.${layout.domain}" ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.fleet-deployer.listen.port}";
        extraConfig = proxyHeaders;
      };
    };

    virtualHosts."pihole" = {
      default = true;
      serverName = "ronove";
      serverAliases = [ "ronove.${layout.domain}" config.services.pihole-web.hostName ];
      locations."/" = {
        proxyPass = "http://${config.pihole.webBackend}";
        extraConfig = proxyHeaders;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];
}
