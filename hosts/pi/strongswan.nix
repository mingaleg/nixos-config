{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  # Agenix secrets
  age.secrets.vpn-users = {
    file = ../../secrets/vpn-users.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  age.secrets.gcp-dns-credentials = {
    file = ../../secrets/gcp-dns-credentials.age;
    owner = "acme";
    group = "acme";
    mode = "0400";
  };

  # ACME/Let's Encrypt configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = "oleg@mingalev.net";

    certs."home.mingalev.net" = {
      domain = "home.mingalev.net";
      dnsProvider = "gcloud";
      environmentFile = config.age.secrets.gcp-dns-credentials.path;
      # Reload StrongSwan when cert renews
      reloadServices = [ "strongswan-swanctl" ];
      group = "acme";
    };
  };

  # Grant strongswan access to certificates
  users.groups.acme = {};
  systemd.services.strongswan-swanctl.serviceConfig.SupplementaryGroups = [ "acme" ];

  services.strongswan-swanctl = {
    enable = true;
    swanctl = {
      connections = {
        ikev2-eap = {
          version = 2;

          local_addrs = [ "%any" ];
          remote_addrs = [ "%any" ];

          local = {
            main = {
              auth = "pubkey";
              # Will be updated to use ACME certs
              certs = [ "/var/lib/acme/home.mingalev.net/fullchain.pem" ];
              id = "home.mingalev.net";
            };
          };

          remote = {
            main = {
              auth = "eap-mschapv2";
              eap_id = "%any";
            };
          };

          children = {
            ikev2-eap = {
              local_ts = [ "0.0.0.0/0" ];  # Full tunnel
              esp_proposals = [ "aes256-sha256" "aes128-sha256" ];
            };
          };

          pools = [ "vpn-pool" ];
          proposals = [ "aes256-sha256-modp2048" "aes128-sha256-modp2048" ];
        };
      };

      pools = {
        vpn-pool = {
          addrs = "172.26.249.161-172.26.249.174";
          dns = [ layout.machines.pi.ip ];  # Pi-hole
        };
      };

      secrets = {
        # Private key for server authentication
        private = {
          server-key = {
            file = "/var/lib/acme/home.mingalev.net/key.pem";
          };
        };

        # EAP user credentials from agenix
        eap.mingaleg = {
          id.main = "mingaleg";
          secret = config.age.secrets.vpn-users.path;
        };
      };
    };
  };

  # Open firewall ports
  networking.firewall = {
    # IKEv2/IPsec ports
    allowedUDPPorts = [ 500 4500 ];

    # Allow DNS from VPN clients to Pi-hole
    # (Pi-hole already opens port 53, but this ensures VPN subnet access)
    interfaces."end0" = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };

  # NAT for VPN clients (full tunnel - route internet through Pi)
  networking.nat = {
    enable = true;
    externalInterface = "end0";
    internalIPs = [ "172.26.249.160/28" ];
  };

  # Dynamic DNS update service
  systemd.services.update-home-dns = {
    description = "Update home.mingalev.net DNS to current external IP";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "update-dns" ''
        set -e

        CREDS_FILE="${config.age.secrets.gcp-dns-credentials.path}"

        # Activate service account
        ${pkgs.google-cloud-sdk}/bin/gcloud auth activate-service-account --key-file="$CREDS_FILE"

        CURRENT_IP=$(${pkgs.curl}/bin/curl -s https://api.ipify.org)
        PROJECT="mingaleg"
        ZONE="mingalev-net"
        DOMAIN="home.mingalev.net."

        echo "Current external IP: $CURRENT_IP"

        # Update DNS record
        ${pkgs.google-cloud-sdk}/bin/gcloud dns record-sets update "$DOMAIN" \
          --rrdatas="$CURRENT_IP" \
          --type=A \
          --ttl=300 \
          --zone="$ZONE" \
          --project="$PROJECT" || {
            echo "Update failed, trying to create record instead..."
            ${pkgs.google-cloud-sdk}/bin/gcloud dns record-sets create "$DOMAIN" \
              --rrdatas="$CURRENT_IP" \
              --type=A \
              --ttl=300 \
              --zone="$ZONE" \
              --project="$PROJECT"
          }

        echo "DNS updated successfully to $CURRENT_IP"
      '';
    };
  };

  systemd.timers.update-home-dns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";  # Check every 5 minutes
      RandomizedDelaySec = "30s";
    };
  };
}
