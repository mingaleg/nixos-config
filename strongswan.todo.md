# StrongSwan VPN Setup for Pi

## Overview

| Setting | Value |
|---------|-------|
| VPN Server | Pi (`172.26.249.253`) |
| VPN Protocol | IKEv2/IPsec |
| Authentication | EAP-MSCHAPv2 (username/password) |
| Tunnel Mode | Full tunnel (all client traffic) |
| DNS for clients | Pi-hole (`172.26.249.253`) |
| VPN Client Subnet | `172.26.249.160/28` (.161-.174, 14 usable) |
| External Access | `home.mingalev.net` (Google Cloud DNS, auto-updated) |
| Server Certificate | Let's Encrypt via DNS-01 challenge (GCP) |

## Prerequisites

### 1. Router Configuration (Linksys)

#### Port Forwarding
Forward these ports to Pi (`172.26.249.253`):
- UDP 500 (IKE)
- UDP 4500 (NAT-Traversal)

#### Static Route
| Field | Value |
|-------|-------|
| Route name | `VPN-clients` |
| Destination IP | `172.26.249.160` |
| Subnet mask | `255.255.255.240` |
| Gateway | `172.26.249.253` |
| Interface | LAN |

### 2. Server Certificate

EAP-MSCHAPv2 still requires a server certificate so clients can verify they're connecting to the real server. Options:

**Option A: Let's Encrypt (Recommended)**
- Use ACME/certbot for `home.mingalev.net`
- Auto-renewal
- Trusted by all clients without manual cert import

**Option B: Self-signed CA**
- Generate your own CA and server cert
- Must import CA cert on all clients
- More control, no external dependency

---

## Server Setup (Pi)

### Step 1: Enable IP Forwarding

Add to `hosts/pi/default.nix`:
```nix
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
```

### Step 2: StrongSwan Configuration

Create `hosts/pi/strongswan.nix`:
```nix
{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
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
              certs = [ "server.crt" ];
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
          dns = [ "172.26.249.253" ];  # Pi-hole
        };
      };

      secrets = {
        eap-user1 = {
          id = "mingaleg";
          secret = "PLACEHOLDER";  # Use agenix/sops-nix for real secret
        };
        # Add more users as needed
      };
    };
  };

  # Open firewall ports
  networking.firewall = {
    allowedUDPPorts = [ 500 4500 ];
  };

  # NAT for VPN clients (full tunnel - route internet through Pi)
  networking.nat = {
    enable = true;
    externalInterface = "end0";
    internalIPs = [ "172.26.249.160/28" ];
  };
}
```

### Step 3: Import Module

In `hosts/pi/default.nix`, add to imports:
```nix
imports = [
  ./hardware-configuration.nix
  ./samba-server.nix
  ./pihole.nix
  ./strongswan.nix  # Add this
];
```

### Step 4: Certificate Setup (Let's Encrypt + Google Cloud DNS)

#### 4a. Create Google Cloud Service Account

1. Go to Google Cloud Console > IAM & Admin > Service Accounts
2. Create a service account (e.g., `acme-dns01`)
3. Grant role: `DNS Administrator` (or custom role with `dns.changes.create`, `dns.changes.get`, `dns.managedZones.list`, `dns.resourceRecordSets.list`)
4. Create JSON key and download it
5. Store the key securely (we'll use agenix/sops-nix)

#### 4b. ACME Configuration

```nix
{ config, ... }:

{
  # Store the GCP credentials securely
  age.secrets.gcp-dns-credentials = {
    file = ../../secrets/gcp-dns-credentials.age;
    owner = "acme";
    group = "acme";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "your-email@example.com";

    certs."home.mingalev.net" = {
      domain = "home.mingalev.net";
      dnsProvider = "gcloud";
      credentialFiles = {
        GCE_SERVICE_ACCOUNT_FILE = config.age.secrets.gcp-dns-credentials.path;
        GCE_PROJECT = "your-gcp-project-id";  # Or use credentialFiles for this too
      };
      # Reload StrongSwan when cert renews
      reloadServices = [ "strongswan-swanctl" ];
    };
  };

  # Grant strongswan-swanctl access to certs
  users.users.strongswan = {
    extraGroups = [ "acme" ];
  };
}
```

#### 4c. StrongSwan Certificate Paths

The ACME certs will be at:
- Cert: `/var/lib/acme/home.mingalev.net/cert.pem`
- Key: `/var/lib/acme/home.mingalev.net/key.pem`
- Chain: `/var/lib/acme/home.mingalev.net/chain.pem`
- Full chain: `/var/lib/acme/home.mingalev.net/fullchain.pem`

Update StrongSwan config to reference these:
```nix
services.strongswan-swanctl.swanctl = {
  connections.ikev2-eap.local.main = {
    auth = "pubkey";
    certs = [ "/var/lib/acme/home.mingalev.net/fullchain.pem" ];
    id = "home.mingalev.net";
  };

  # Private key for server authentication
  secrets.private = {
    server-key = {
      file = "/var/lib/acme/home.mingalev.net/key.pem";
    };
  };
};
```

#### 4d. Dynamic DNS Update (for external IP)

Since your external IP changes, add a service to update the DNS record. Using `google-cloud-sdk`:

```nix
# In a separate module or same file
{ pkgs, config, ... }:

{
  systemd.services.update-home-dns = {
    description = "Update home.mingalev.net DNS to current external IP";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "update-dns" ''
        set -e
        export GOOGLE_APPLICATION_CREDENTIALS="${config.age.secrets.gcp-dns-credentials.path}"

        CURRENT_IP=$(${pkgs.curl}/bin/curl -s https://api.ipify.org)
        ZONE="mingalev-net"  # Your Cloud DNS zone name

        ${pkgs.google-cloud-sdk}/bin/gcloud dns record-sets update home.mingalev.net. \
          --rrdatas="$CURRENT_IP" \
          --type=A \
          --ttl=300 \
          --zone="$ZONE"
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
```

### Step 5: Secrets Management

For EAP passwords, use `agenix` or `sops-nix` instead of plaintext:
```nix
# Example with agenix
age.secrets.vpn-users = {
  file = ../../secrets/vpn-users.age;
};

services.strongswan-swanctl.swanctl.secrets = {
  eap-user1 = {
    id = "mingaleg";
    secret = { file = config.age.secrets.vpn-users.path; };
  };
};
```

---

## Client Setup

### NixOS Clients

Option A: NetworkManager plugin (GUI-friendly)
```nix
networking.networkmanager = {
  enable = true;
  plugins = [ pkgs.networkmanager-strongswan ];
};
```

Option B: Direct swanctl (headless/scripted)
```nix
services.strongswan-swanctl = {
  enable = true;
  swanctl.connections.home = {
    version = 2;
    remote_addrs = [ "home.mingalev.net" ];
    vips = [ "0.0.0.0" ];  # Request virtual IP from server

    local = {
      main = {
        auth = "eap";
        eap_id = "mingaleg";
      };
    };

    remote = {
      main = {
        auth = "pubkey";
        id = "home.mingalev.net";
      };
    };

    children = {
      home = {
        remote_ts = [ "0.0.0.0/0" ];
        start_action = "none";  # Manual connect
      };
    };
  };

  secrets = {
    eap-me = {
      id = "mingaleg";
      secret = "...";  # Use secrets management
    };
  };
};
```

Connect: `swanctl --initiate --child home`
Disconnect: `swanctl --terminate --child home`

### Android Clients

**Option A: Native Android VPN (Settings > Network > VPN)**
1. Add VPN profile
2. Type: IKEv2/IPSec MSCHAPv2
3. Server: `home.mingalev.net`
4. Username: your EAP username
5. Password: your EAP password
6. Server certificate: (auto if Let's Encrypt, or import CA if self-signed)

**Option B: StrongSwan App (F-Droid/Play Store)**
- More features and diagnostics
- Import .sswan profile for easy setup

---

## Pi-hole Considerations

VPN clients will use Pi-hole at `172.26.249.253` for DNS. Ensure:

1. Pi-hole listens on the right interface (should already work since it's the same IP)
2. Firewall allows DNS from VPN subnet:
```nix
networking.firewall.interfaces."end0".allowedUDPPorts = [ 53 ];
networking.firewall.interfaces."end0".allowedTCPPorts = [ 53 ];
```

Or if using a virtual interface for VPN, allow on that too.

---

## Testing Checklist

### Infrastructure
- [ ] GCP: Service account created with DNS Admin role
- [ ] GCP: JSON key downloaded and encrypted with agenix
- [ ] Router: Port forwarding UDP 500, 4500 to Pi
- [ ] Router: Static route for 172.26.249.160/28 via Pi

### Pi Server
- [ ] Pi: `sysctl net.ipv4.ip_forward` returns 1
- [ ] Pi: ACME cert exists at `/var/lib/acme/home.mingalev.net/`
- [ ] Pi: `swanctl --list-conns` shows the connection
- [ ] Pi: `swanctl --list-pools` shows the IP pool
- [ ] Pi: `journalctl -u update-home-dns` shows successful DNS updates
- [ ] DNS: `dig home.mingalev.net` returns current external IP

### External Connectivity
- [ ] External: Can reach Pi on UDP 500 from outside (test with nmap or similar)

### Client Tests
- [ ] Client: Can establish VPN connection
- [ ] Client: Gets IP in 172.26.249.160/28 range
- [ ] Client: Can ping Pi (172.26.249.253)
- [ ] Client: Can ping other LAN devices
- [ ] Client: DNS resolves via Pi-hole (check Pi-hole query log)
- [ ] Client: Internet works through tunnel
- [ ] Client: Check https://whatismyip.com shows home external IP

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `hosts/pi/strongswan.nix` | Create - main StrongSwan config |
| `hosts/pi/default.nix` | Modify - import strongswan.nix, add ip_forward |
| `secrets/vpn-users.age` | Create - EAP credentials (agenix) |
| `secrets/gcp-dns-credentials.age` | Create - GCP service account JSON (agenix) |
| Google Cloud Console | Create service account with DNS Admin role |
| Router admin panel | Configure - port forward + static route |

## Secrets Setup (agenix)

If not already using agenix, add to flake.nix:
```nix
inputs.agenix.url = "github:ryantm/agenix";

# In Pi modules:
agenix.nixosModules.default
```

Create `secrets/secrets.nix`:
```nix
let
  pi = "ssh-ed25519 AAAA...";  # Pi's host key
  mingaleg = "ssh-ed25519 AAAA...";  # Your user key
in {
  "vpn-users.age".publicKeys = [ pi mingaleg ];
  "gcp-dns-credentials.age".publicKeys = [ pi mingaleg ];
}
```

Encrypt secrets:
```bash
cd secrets
agenix -e vpn-users.age        # Enter EAP password
agenix -e gcp-dns-credentials.age  # Paste GCP JSON key
```

---

## Security Notes

1. **EAP passwords**: Use strong, unique passwords per user
2. **Server cert**: Let's Encrypt preferred (trusted, auto-renews)
3. **Firewall**: Only expose UDP 500/4500, nothing else
4. **Logs**: StrongSwan logs to journal - `journalctl -u strongswan-swanctl`
5. **Updates**: Keep NixOS and StrongSwan updated for security patches

---

## Future Enhancements (Optional)

- [ ] Set up monitoring/alerts for VPN service
- [ ] Add split-tunnel profile as alternative
- [ ] Automate client config generation (.sswan profiles for Android)
