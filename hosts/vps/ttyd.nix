{ config, pkgs, lib, ... }:

{
  age.secrets.ttyd-password = {
    file = ../../secrets/ttyd-password.age;
    owner = "root";
    mode = "0400";
  };

  # Web terminal for mingaleg. Bound to loopback only - nginx terminates TLS
  # and proxies in, so ttyd itself never faces the network.
  services.ttyd = {
    enable = true;
    interface = "lo";
    port = 7681;

    # Read at start via systemd LoadCredential, so the password never enters
    # the nix store. Plaintext copy lives at /mnt/pegasus/secrets/ttyd-password.
    username = "mingaleg";
    passwordFile = config.age.secrets.ttyd-password.path;

    # The module deliberately has no default here, to force a decision.
    writeable = true;

    # `entrypoint` stays at its default (shadow's `login`): the agenix password
    # only gets you as far as a login prompt, and mingaleg's system password is
    # a second, independent gate. Worth keeping on an internet-facing host.
    # For a shell straight away instead, set user = "mingaleg" and
    # entrypoint = [ "${pkgs.bashInteractive}/bin/bash" ].

    # Reject websocket upgrades whose Origin does not match the Host header.
    checkOrigin = true;
    maxClients = 3;
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # home-gw.mingalev.net is the only name with an A record pointing here
    # (34.39.81.90); *.mingalev.net resolves elsewhere, so this is the name
    # HTTP-01 can validate against. A dedicated name just needs an A record
    # added in Cloud DNS and this string changed.
    virtualHosts."home-gw.mingalev.net" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:7681";
        proxyWebsockets = true;
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "oleg@mingalev.net";
  };

  # 80 for the ACME HTTP-01 challenge and the redirect to 443.
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
