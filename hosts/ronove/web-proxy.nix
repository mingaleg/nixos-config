{ config, lib, ... }:

# nginx owns port 80 on ronove and routes by name: fleet-deployer.ronove to the
# deployer, docs.ronove to mingadocs, anything else (ronove, pi.hole, the bare
# IP) to the Pi-hole web interface, which pihole.webProxied moves to loopback.
# pegasus.ronove lives with the rest of the file share in nginx-www.nix.

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

  # mingadocs has no login of its own, and serves personal documents.
  lanAndVpnOnly = ''
    allow ${layout.network.prefix}.0/${toString layout.network.prefixLength};
    allow 10.100.0.0/24; # WireGuard VPN clients (via vps)
    allow 127.0.0.1;
    deny all;
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

    virtualHosts."docs.ronove" = {
      serverAliases = [ "docs.ronove.${layout.domain}" ];
      extraConfig = lanAndVpnOnly;
      locations."/" = {
        proxyPass = "http://${config.services.mingadocs.listen.address}:${toString config.services.mingadocs.listen.port}";
        # A scan request can wait on the scanner for a while.
        extraConfig = proxyHeaders + ''
          proxy_read_timeout 300s;
        '';
      };
      # With DEBUG off the app serves neither of these itself.
      locations."/static/".alias = "${config.services.mingadocs.staticDir}/";
      locations."/media/".alias = "${config.services.mingadocs.mediaDir}/";
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
