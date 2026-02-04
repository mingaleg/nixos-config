# StrongSwan VPN Setup for Pi

## 🎯 Current Status

**NixOS Configuration: ✅ COMPLETE**
All NixOS configuration files have been created and deployed successfully.

**Server Status: ✅ WORKING**
All services on Pi are running correctly:
- StrongSwan VPN server running and configured
- Let's Encrypt certificate obtained
- Dynamic DNS updating successfully
- Firewall rules configured
- NAT configured

**VPN Connection: ⚠️ BLOCKED BY ISP CGNAT**
Cannot connect from external clients due to Carrier-Grade NAT.
- Router has private IP (100.76.193.146) instead of public IP
- ISP uses shared public IP (185.241.165.36) for multiple customers
- Port forwarding impossible without real public IP

**Next Action Required:** Contact ISP to request a public IP address, or implement VPS relay solution.

---

## 📋 Next Steps (Manual Actions Required)

### 1. Update Configuration TODOs ✅
- [x] `hosts/pi/strongswan.nix` line ~24: Replace `"your-email@example.com"` with your actual email
- [x] `hosts/pi/strongswan.nix` line ~68: Replace `"mingalev-net"` with your actual GCP Cloud DNS zone name

### 2. Google Cloud Platform Setup ✅
- [x] Create service account `acme-dns01` with DNS Administrator role
- [x] Download JSON key (`mingaleg-net-acme-dns01.json`)
- [x] Create/verify Cloud DNS zone exists
- [x] Create initial DNS A record for `home.mingalev.net`

### 3. Create Encrypted Secrets ✅
- [x] `secrets/vpn-users.age` - Created
- [x] `secrets/gcp-dns-credentials.age` - Created

```bash
cd secrets
cat ../mingaleg-net-acme-dns01.json | EDITOR="tee" agenix -e gcp-dns-credentials.age -i ../ssh-keys/agenix-hosts
printf "YOUR_PASSWORD" | EDITOR="tee" agenix -e vpn-users.age -i ../ssh-keys/agenix-hosts
```

### 4. Deploy Private Key to Pi ✅
```bash
scp ssh-keys/agenix-hosts mingaleg@pi:/tmp/ && ssh -t mingaleg@pi 'sudo mkdir -p /root/.ssh && sudo mv /tmp/agenix-hosts /root/.ssh/ && sudo chmod 600 /root/.ssh/agenix-hosts && sudo chown root:root /root/.ssh/agenix-hosts && sudo ls -la /root/.ssh/agenix-hosts && echo OK'
```
- [x] Key deployed to `/root/.ssh/agenix-hosts` with permissions `-rw------- 1 root root`
- **IMPORTANT:** Backup `ssh-keys/agenix-hosts` securely!

### 5. Router Configuration ✅
- [x] Port forward UDP 500 → Pi (172.26.249.253)
- [x] Port forward UDP 4500 → Pi (172.26.249.253)
- [x] Add static route: 172.26.249.160/28 via 172.26.249.253
- ⚠️ **Note:** Router behind CGNAT - port forwarding ineffective until public IP obtained

### 6. Deploy to Pi ✅
```bash
nix flake update
sudo nixos-rebuild switch --flake .#pi
```

### 7. Verify Services ✅
- [x] Check IP forwarding: `sysctl net.ipv4.ip_forward` → Returns 1 ✅
- [x] Check StrongSwan: `sudo systemctl status strongswan-swanctl` → Running ✅
- [x] Check ACME cert: `sudo ls -la /var/lib/acme/home.mingalev.net/` → All certs present ✅
- [x] Check DNS update: `sudo journalctl -u update-home-dns` → Working, updating to 185.241.165.36 ✅
- [x] Check StrongSwan config: Connection 'ikev2-eap' loaded, pool 'vpn-pool' loaded ✅
- [x] Check EAP credentials: User 'mingaleg' loaded ✅

### 8. Test VPN Connection ⚠️ BLOCKED BY CGNAT

**Issue Discovered:** ISP uses Carrier-Grade NAT (CGNAT)
- Router WAN IP: `100.76.193.146` (private CGNAT range)
- Public IP: `185.241.165.36` (shared among multiple customers)
- Port forwarding on router doesn't help - ISP gateway doesn't forward to individual customers

**Evidence:**
- ✅ Pi receives packets from local network (172.26.249.254 → 172.26.249.253)
- ❌ Pi receives ZERO packets from external clients
- ✅ Router port forwarding configured correctly (UDP 500, 4500)
- ✅ Router firewall allows traffic
- ❌ Packets never reach the router from internet

**Solutions:**

#### Option 1: Request Public IP from ISP (Recommended)
- Contact ISP and request a real public/static IP address
- Explain need for "remote access" or "home server"
- May cost £5-10/month extra, sometimes free
- Once obtained, VPN will work immediately with current config

#### Option 2: VPS Relay
- Deploy a cheap VPS (£3-5/month) with public IP
- Run WireGuard on VPS
- Create permanent tunnel: Pi ↔ VPS
- VPN clients connect to VPS, which relays to Pi
- Requires additional configuration

#### Option 3: Tailscale/ZeroTier
- Mesh VPN service that works through CGNAT
- No port forwarding needed
- Different architecture than traditional VPN
- Easiest workaround but requires Tailscale/ZeroTier on all clients

---

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

### Step 1: Enable IP Forwarding ✅

**Status:** Complete

Added to `hosts/pi/default.nix`:
```nix
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
```

### Step 2: StrongSwan Configuration ✅

**Status:** Complete - See `hosts/pi/strongswan.nix`

Original example:
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

### Step 3: Import Module ✅

**Status:** Complete

Added to `hosts/pi/default.nix` imports:
```nix
./strongswan.nix
```

### Step 4: Certificate Setup (Let's Encrypt + Google Cloud DNS) ✅

**Status:** NixOS config complete, manual GCP setup required

#### 4a. Create Google Cloud Service Account ⏳

1. Go to Google Cloud Console > IAM & Admin > Service Accounts
2. Create a service account (e.g., `acme-dns01`)
3. Grant role: `DNS Administrator` (or custom role with `dns.changes.create`, `dns.changes.get`, `dns.managedZones.list`, `dns.resourceRecordSets.list`)
4. Create JSON key and download it
5. Store the key securely (we'll use agenix/sops-nix)

#### 4b. ACME Configuration ✅

**Status:** Complete - Configured in `hosts/pi/strongswan.nix`

ACME is configured with:
- Let's Encrypt with GCP DNS-01 challenge
- Auto-renewal configured
- StrongSwan reload on renewal
- Email: **TODO - Update in config**
- GCP Zone: **TODO - Update in config**

#### 4c. StrongSwan Certificate Paths ✅

**Status:** Complete - Configured in `hosts/pi/strongswan.nix`

ACME certs will be at:
- Cert: `/var/lib/acme/home.mingalev.net/cert.pem`
- Key: `/var/lib/acme/home.mingalev.net/key.pem`
- Chain: `/var/lib/acme/home.mingalev.net/chain.pem`
- Full chain: `/var/lib/acme/home.mingalev.net/fullchain.pem`

StrongSwan references these paths (already configured in `hosts/pi/strongswan.nix`).

#### 4d. Dynamic DNS Update (for external IP) ✅

**Status:** Complete - Configured in `hosts/pi/strongswan.nix`

Dynamic DNS update service configured:

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

### Step 5: Secrets Management ✅

**Status:** NixOS config complete, need to create encrypted secret files

Agenix configuration is complete in `hosts/pi/strongswan.nix`.

**Manual action required:** Create the encrypted secret files:
```bash
cd secrets
agenix -e vpn-users.age              # Enter your VPN password
agenix -e gcp-dns-credentials.age    # Paste GCP service account JSON
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

## Pi-hole Considerations ✅

**Status:** Complete - Configured in `hosts/pi/strongswan.nix`

VPN clients will use Pi-hole at `172.26.249.253` for DNS.

- ✅ Pi-hole already listens on the interface
- ✅ Firewall rules added for DNS from VPN subnet (ports 53 TCP/UDP on end0)
- ✅ VPN pool configured to push Pi-hole DNS to clients

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

## Files Created/Modified

| File | Status | Description |
|------|--------|-------------|
| `hosts/pi/strongswan.nix` | ✅ Created | Complete StrongSwan + ACME + DNS update config |
| `hosts/pi/default.nix` | ✅ Modified | Added IP forwarding, agenix identity, strongswan import |
| `flake.nix` | ✅ Modified | Added agenix input and module |
| `secrets/secrets.nix` | ✅ Created | Agenix secrets definition |
| `ssh-keys/agenix-hosts.pub` | ✅ Created | Public key (safe to commit) |
| `ssh-keys/agenix-hosts` | ✅ Created | Private key (in .gitignore, BACKUP SECURELY!) |
| `.gitignore` | ✅ Updated | Protects private key from commits |
| `secrets/vpn-users.age` | ✅ Created | Encrypted VPN password |
| `secrets/gcp-dns-credentials.age` | ✅ Created | Encrypted GCP service account JSON |
| `modules/core-desktop/system-packages.nix` | ✅ Modified | Added agenix CLI tool |
| Google Cloud Console | ✅ Done | Service account `acme-dns01` created |
| Cloud DNS | ✅ Done | A record `home.mingalev.net` created |
| Router admin panel | ✅ Done | Port forwarding + static route configured |
| Pi: `/root/.ssh/agenix-hosts` | ✅ Deployed | Private key deployed to Pi |

## Secrets Setup (agenix) ✅

**Status:** Infrastructure complete, need to create encrypted files

### What's Been Done:
- ✅ Added agenix to `flake.nix`
- ✅ Added agenix module to Pi configuration
- ✅ Created `secrets/secrets.nix` with key definitions
- ✅ Generated global agenix host key pair (`ssh-keys/agenix-hosts{,.pub}`)
- ✅ Configured agenix identity path in `hosts/pi/default.nix`

### What You Need to Do:

**1. Install agenix CLI (if not already installed):**
```bash
nix profile install github:ryantm/agenix
```

**2. Create encrypted secret files:**
```bash
cd secrets
agenix -e vpn-users.age              # Enter VPN password for user 'mingaleg'
agenix -e gcp-dns-credentials.age    # Paste entire GCP JSON key
```

**3. Deploy private key to Pi:**
```bash
scp /home/mingaleg/nixos-config/ssh-keys/agenix-hosts mingaleg@pi:/tmp/
# Then on Pi:
sudo mkdir -p /root/.ssh
sudo mv /tmp/agenix-hosts /root/.ssh/
sudo chmod 600 /root/.ssh/agenix-hosts
sudo chown root:root /root/.ssh/agenix-hosts
```

**IMPORTANT:** Backup `ssh-keys/agenix-hosts` securely (password manager, encrypted drive, etc.)

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
