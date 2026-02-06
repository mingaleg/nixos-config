# WireGuard-Only VPN Setup (Simpler Alternative)

## Overview

This is a **simpler alternative** to the StrongSwan + VPS relay approach. Instead of relaying IKEv2/IPsec through a VPS to StrongSwan on the Pi, we use WireGuard for everything:

```
VPN Client → VPS (WireGuard) → Pi (WireGuard) → Home Network
```

**Advantages over StrongSwan approach:**
- ✅ Simpler configuration (no StrongSwan, no ACME certs needed)
- ✅ Better performance (WireGuard is faster than IKEv2/IPsec)
- ✅ Modern cryptography (Noise protocol, ChaCha20, Poly1305)
- ✅ Smaller attack surface
- ✅ Easier to debug
- ✅ Native apps on all platforms (iOS, Android, Windows, macOS, Linux)
- ✅ Battery-friendly on mobile devices

**Differences from StrongSwan:**
- ❌ Uses WireGuard protocol instead of IKEv2/IPsec
- ❌ Not compatible with native OS VPN settings (requires WireGuard app)
- ✅ But WireGuard apps are excellent on all platforms

**Cost:** Same ~$10/month for GCP e2-micro VPS

---

## Architecture

```
┌─────────────────────┐
│  VPN Client         │ Laptop, phone, etc.
│  WireGuard app      │ 10.100.0.x/24
└──────────┬──────────┘
           │
           │ WireGuard VPN
           │ (encrypted)
           ▼
┌─────────────────────┐
│  GCP VPS            │ Public IP
│  (NixOS)            │ 10.100.0.1/24 (clients)
│                     │ 10.200.0.1/24 (to Pi)
└──────────┬──────────┘
           │
           │ WireGuard tunnel
           │ (encrypted)
           ▼
┌─────────────────────┐
│  Pi                 │ Behind CGNAT
│  (NixOS)            │ 10.200.0.2/24
│                     │
│  - Pi-hole (DNS)    │
│  - Samba (files)    │
│  - Home network     │
└─────────────────────┘
           │
           ▼
      Home Network
    (All devices accessible)
```

**Two WireGuard tunnels:**
1. **Client ↔ VPS:** VPN clients connect here (10.100.0.0/24)
2. **VPS ↔ Pi:** Permanent tunnel through CGNAT (10.200.0.0/24)

**Routing:**
- Client sends packet to 172.26.249.0/24 (your home network)
- VPS routes it through Pi tunnel
- Pi routes to home network devices

---

## Prerequisites

- ✅ GCP account (you already have one)
- ✅ Google Cloud SDK installed (added to home.nix)
- ✅ WireGuard tools installed (added to modules/core-desktop/system-packages.nix)
- ✅ Your existing Pi configuration
- ✅ SSH access to Pi
- ✅ StrongSwan disabled on Pi (commented out in hosts/pi/default.nix)

---

## Part 0: Reserve Static IP

✅ **COMPLETED**

Reserve a static IP address in GCP to ensure the VPS IP doesn't change:

```bash
gcloud compute addresses create vps-static-ip --region=europe-west2 --project=mingaleg
```

Get the IP address:
```bash
gcloud compute addresses describe vps-static-ip --region=europe-west2 --format='get(address)' --project=mingaleg
```

**Reserved IP: 34.39.81.90**

---

## Part 1: Build & Deploy NixOS VPS

### 1. Build NixOS GCE Image

✅ **COMPLETED**

Built NixOS 25.11 GCE image using official nixpkgs script.

**Image name:** `nixos-image-google-compute-25-11pre-git-x86-64-linux`
**Status:** READY
**Location:** `gs://nixos-images-mingaleg/nixos-image-google-compute-25.11pre-git-x86_64-linux.raw.tar.gz`

### 2. Create VPS Instance

✅ **COMPLETED**

Created VPS instance with static IP.

**Instance:** `vps`
**Zone:** `europe-west2-a`
**IP:** `34.39.81.90`
**Status:** RUNNING

### 3. Create Firewall Rules

✅ **COMPLETED**

Created all required firewall rules:

```bash
# WireGuard VPN port
gcloud compute firewall-rules create wireguard-vpn \
  --allow=udp:51820 \
  --target-tags=wireguard-vps \
  --description="WireGuard VPN for clients" \
  --project mingaleg

# WireGuard tunnel to Pi
gcloud compute firewall-rules create wireguard-tunnel \
  --allow=udp:51821 \
  --target-tags=wireguard-vps \
  --description="WireGuard tunnel to Pi" \
  --project mingaleg

# SSH
gcloud compute firewall-rules create wireguard-ssh \
  --allow=tcp:22 \
  --target-tags=wireguard-vps \
  --description="SSH access" \
  --project mingaleg
```

### 4. Verify VPS and Set IP Variable

```bash
# Set the static IP as a variable for later use
VPS_IP=34.39.81.90

# Verify the VPS is running
gcloud compute instances describe vps \
  --zone=europe-west2-a \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
  --project mingaleg
```

Should output: `34.39.81.90`

---

## Part 2: Generate All WireGuard Keys

✅ **COMPLETED**

Generated WireGuard keys for:
- VPS (server keys)
- Pi (tunnel endpoint keys)
- Pixel10 (client keys for testing)

Keys stored in `tmp/` directory. Private keys encrypted with agenix and stored in `secrets/wireguard-vps-private.age` and `secrets/wireguard-pi-private.age`.

Updated `secrets/secrets.nix` to include WireGuard key entries.

---

## Part 3: Configure VPS

✅ **COMPLETED**

Created configuration files:
- `hosts/vps/default.nix` - Main VPS configuration
- `hosts/vps/wireguard.nix` - WireGuard configuration with two interfaces:
  - `wg-pi` (port 51821) - Tunnel to Pi
  - `wg-clients` (port 51820) - VPN for clients

---

## Part 4: Configure Pi

✅ **COMPLETED**

Created `hosts/pi/wireguard-vpn.nix` with WireGuard configuration:
- Interface `wg0` (port 51821) - Connects to VPS
- Added to `hosts/pi/default.nix` imports

---

## Part 5: Add to Flake and Test Build

✅ **COMPLETED**

Added VPS configuration to `flake.nix`.

Tested local builds:
- ✅ VPS config builds successfully
- ✅ Pi config builds successfully

---

## Part 6: Deploy to VPS

### 1. Deploy Agenix Host Key

First, deploy the agenix host key so the VPS can decrypt secrets:

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./wireguard.nix
  ];

  networking.hostName = "vps";

  # Google Compute Engine support
  virtualisation.googleComputeImage.enable = true;

  # User configuration
  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  # Agenix
  age.identityPaths = [ "/root/.ssh/agenix-hosts" ];

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    tcpdump
    wireguard-tools
  ];

  # Enable IP forwarding for routing
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 51820 51821 ];

    # Allow forwarding between WireGuard interfaces
    extraCommands = ''
      iptables -A FORWARD -i wg-clients -o wg-pi -j ACCEPT
      iptables -A FORWARD -i wg-pi -o wg-clients -j ACCEPT
      iptables -t nat -A POSTROUTING -o wg-pi -j MASQUERADE
    '';
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
```

### 3. Create `hosts/vps/wireguard.nix`

```nix
{ config, pkgs, ... }:

{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-vps-private = {
    file = ../../secrets/wireguard-vps-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wireguard.interfaces = {
    # Tunnel to Pi (permanent connection through CGNAT)
    wg-pi = {
      ips = [ "10.200.0.1/24" ];
      listenPort = 51821;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;

      peers = [
        {
          # Pi
          publicKey = "PI_PUBLIC_KEY_HERE";  # Replace with Pi's public key
          allowedIPs = [
            "10.200.0.2/32"           # Pi's tunnel IP
            "172.26.249.0/24"         # Home network
          ];
          persistentKeepalive = 25;
        }
      ];
    };

    # VPN for clients (laptops, phones, etc.)
    wg-clients = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;

      # Clients will be added here
      peers = [
        {
          # Laptop
          publicKey = "LAPTOP_PUBLIC_KEY_HERE";  # Replace with laptop's public key
          allowedIPs = [ "10.100.0.10/32" ];
        }
        {
          # Phone
          publicKey = "PHONE_PUBLIC_KEY_HERE";   # Replace with phone's public key
          allowedIPs = [ "10.100.0.11/32" ];
        }
        # Add more clients as needed with IPs 10.100.0.12, .13, etc.
      ];

      # Route client traffic to home network through Pi tunnel
      postSetup = ''
        ${pkgs.iproute2}/bin/ip route add 172.26.249.0/24 via 10.200.0.2 dev wg-pi
      '';

      postShutdown = ''
        ${pkgs.iproute2}/bin/ip route del 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
      '';
    };
  };
}
```

Replace the placeholder public keys with actual keys from Part 2.

---

## Part 4: Configure Pi

### 1. Create `hosts/pi/wireguard-vpn.nix`

```nix
{ config, pkgs, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-pi-private = {
    file = ../../secrets/wireguard-pi-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.200.0.2/24" ];
      listenPort = 51821;
      privateKeyFile = config.age.secrets.wireguard-pi-private.path;

      peers = [
        {
          # VPS
          publicKey = "VPS_PUBLIC_KEY_HERE";  # Replace with VPS's public key
          allowedIPs = [
            "10.200.0.1/32"    # VPS tunnel IP
            "10.100.0.0/24"    # VPN clients
          ];
          endpoint = "VPS_PUBLIC_IP:51821";  # Replace with VPS's public IP
          persistentKeepalive = 25;
        }
      ];

      # NAT for VPN clients accessing home network
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o end0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -o end0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
      '';

      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o end0 -j MASQUERADE || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -o end0 -j ACCEPT || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT || true
      '';
    };
  };

  # Open WireGuard port
  networking.firewall.allowedUDPPorts = [ 51821 ];
}
```

Replace:
- `VPS_PUBLIC_KEY_HERE` with VPS's public key
- `VPS_PUBLIC_IP` with VPS's actual public IP

### 2. Update `hosts/pi/default.nix`

Add to imports:

```nix
imports = [
  ./hardware-configuration.nix
  ./samba-server.nix
  ./pihole.nix
  ./wireguard-vpn.nix  # Add this (instead of strongswan.nix)
];
```

**Note:** You can keep strongswan.nix in imports if you want both options, or remove it if going WireGuard-only.

---

## Part 5: Add VPS to Flake

Update `flake.nix`:

```nix
nixosConfigurations = {
  "minganix" = nixpkgs.lib.nixosSystem {
    # ... existing config
  };

  "mingamini" = nixpkgs.lib.nixosSystem {
    # ... existing config
  };

  "pi" = nixos-raspberrypi.lib.nixosSystem {
    # ... existing config
  };

  # Add VPS
  "vps" = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = inputs;
    modules = [
      agenix.nixosModules.default
      ./hosts/vps
    ];
  };
};
```

---

## Part 6: Deploy Everything

### 1. Deploy Private Key to VPS

```bash
scp ssh-keys/agenix-hosts mingaleg@VPS_PUBLIC_IP:/tmp/
ssh mingaleg@VPS_PUBLIC_IP 'sudo mkdir -p /root/.ssh && sudo mv /tmp/agenix-hosts /root/.ssh/ && sudo chmod 600 /root/.ssh/agenix-hosts && sudo chown root:root /root/.ssh/agenix-hosts'
```

Replace `VPS_PUBLIC_IP` with actual IP.

### 2. Deploy to VPS

```bash
./deploy_remote vps
```

### 3. Deploy to Pi

```bash
./deploy_remote pi
```

---

## Part 7: Configure VPN Clients

### Laptop (NixOS)

Add to your laptop's `configuration.nix` or `home.nix`:

```nix
networking.wireguard.interfaces = {
  wg0 = {
    ips = [ "10.100.0.10/24" ];
    privateKeyFile = "/path/to/wireguard-laptop-private";

    peers = [
      {
        # VPS
        publicKey = "VPS_PUBLIC_KEY_HERE";
        allowedIPs = [
          "10.100.0.0/24"      # VPN network
          "10.200.0.0/24"      # Pi tunnel
          "172.26.249.0/24"    # Home network
        ];
        endpoint = "VPS_PUBLIC_IP:51820";
        persistentKeepalive = 25;
      }
    ];
  };
};
```

**Connect:**
```bash
sudo wg-quick up wg0
```

**Disconnect:**
```bash
sudo wg-quick down wg0
```

### Phone (Android/iOS)

1. **Install WireGuard app:**
   - Android: Google Play Store or F-Droid
   - iOS: App Store

2. **Create configuration:**

Create a file `phone.conf`:

```ini
[Interface]
PrivateKey = PHONE_PRIVATE_KEY_HERE
Address = 10.100.0.11/24
DNS = 172.26.249.253

[Peer]
PublicKey = VPS_PUBLIC_KEY_HERE
AllowedIPs = 10.100.0.0/24, 10.200.0.0/24, 172.26.249.0/24
Endpoint = VPS_PUBLIC_IP:51820
PersistentKeepalive = 25
```

3. **Import to phone:**
   - Generate QR code: `qrencode -t ansiutf8 < phone.conf`
   - Or transfer file and import in WireGuard app

### Windows/macOS

Download WireGuard app from https://www.wireguard.com/install/ and use similar config as phone.

---

## Part 8: Verification

### 1. Check WireGuard on VPS

```bash
ssh mingaleg@VPS_PUBLIC_IP 'sudo wg show'
```

Should show:
- `wg-pi` interface with Pi as peer (latest handshake)
- `wg-clients` interface with your connected clients

### 2. Check WireGuard on Pi

```bash
ssh mingaleg@pi 'sudo wg show'
```

Should show:
- `wg0` interface with VPS as peer (latest handshake)

### 3. Test Connectivity

**From laptop (with VPN connected):**

```bash
# Ping Pi through tunnel
ping 172.26.249.253

# Ping other home devices
ping 172.26.249.1   # Router

# Test Pi-hole DNS
nslookup google.com

# Access Samba
smbclient -L //172.26.249.253
```

**Check you're routing through home:**
```bash
curl ifconfig.me   # Should show your HOME's public IP (185.241.165.36)
```

---

## Part 9: Add More Clients

To add a new device:

### 1. Generate keys for new device

```bash
wg genkey | tee wireguard-newdevice-private | wg pubkey > wireguard-newdevice-public
cat wireguard-newdevice-public  # Copy this
```

### 2. Add peer to VPS config

In `hosts/vps/wireguard.nix`, add to `wg-clients.peers`:

```nix
{
  publicKey = "NEWDEVICE_PUBLIC_KEY";
  allowedIPs = [ "10.100.0.20/32" ];  # Use next available IP
}
```

### 3. Deploy to VPS

```bash
./deploy_remote vps
```

### 4. Configure new device

Use the private key and VPS public key to create config.

---

## Troubleshooting

### WireGuard tunnel VPS ↔ Pi not establishing

```bash
# Check VPS logs
ssh mingaleg@VPS_PUBLIC_IP 'sudo journalctl -u systemd-networkd | grep wg'

# Check Pi logs
ssh mingaleg@pi 'sudo journalctl -u systemd-networkd | grep wg'

# Verify firewall allows UDP 51821
ssh mingaleg@VPS_PUBLIC_IP 'sudo iptables -L -n -v | grep 51821'

# Test if Pi can reach VPS
ssh mingaleg@pi 'nc -u -v VPS_PUBLIC_IP 51821'
```

### Client can't connect to VPS

```bash
# Check VPS is listening
ssh mingaleg@VPS_PUBLIC_IP 'sudo ss -ulnp | grep 51820'

# Check GCP firewall
gcloud compute firewall-rules list --filter="name=wireguard-vpn"

# Test from client
nc -u -v VPS_PUBLIC_IP 51820
```

### Can connect but can't reach home network

```bash
# Check routing on VPS
ssh mingaleg@VPS_PUBLIC_IP 'ip route show'

# Should see: 172.26.249.0/24 via 10.200.0.2 dev wg-pi

# Check NAT on Pi
ssh mingaleg@pi 'sudo iptables -t nat -L -n -v'

# Check forwarding enabled
ssh mingaleg@pi 'sysctl net.ipv4.ip_forward'
```

---

## Management

### View Connected Clients

**On VPS:**
```bash
ssh mingaleg@VPS_PUBLIC_IP 'sudo wg show wg-clients'
```

Shows all connected clients with:
- Public key
- Latest handshake time
- Data transfer
- Endpoint IP

### Disconnect a Client

Remove peer from `hosts/vps/wireguard.nix` and redeploy:

```bash
./deploy_remote vps
```

### Rotate Keys

Generate new keys, update configs, redeploy. Old keys are immediately invalid.

### Monitor Traffic

```bash
# On VPS
ssh mingaleg@VPS_PUBLIC_IP 'watch -n 1 sudo wg show wg-clients transfer'

# On Pi
ssh mingaleg@pi 'watch -n 1 sudo wg show wg0 transfer'
```

---

## Comparison: WireGuard vs StrongSwan + Relay

| Aspect | WireGuard-Only | StrongSwan + VPS Relay |
|--------|----------------|------------------------|
| **Complexity** | Lower - one protocol | Higher - two protocols |
| **Performance** | Faster (WireGuard) | Slower (IPsec overhead) |
| **Battery** | Better (efficient) | Worse (more processing) |
| **Native VPN** | No - needs app | Yes - native iOS/Android |
| **Certificates** | Not needed | Need Let's Encrypt |
| **Protocol** | WireGuard only | IKEv2/IPsec |
| **Setup time** | ~1 hour | ~2 hours |
| **Debugging** | Easier | More complex |
| **Cost** | Same (~$10/month) | Same (~$10/month) |

---

## Cost

**GCP e2-micro VM:**
- Compute: ~$7/month
- Network egress: ~$1-3/month
- **Total: ~$10/month**

**Cheaper alternatives:**
- Oracle Cloud Free Tier (free forever!)
- Hetzner Cloud (€3.79/month)
- DigitalOcean ($6/month)

---

## Summary

**What you get:**
- ✅ Full VPN access to home network from anywhere
- ✅ All traffic encrypted with WireGuard
- ✅ Bypasses CGNAT limitation
- ✅ Access to Pi-hole, Samba, all home devices
- ✅ Fully declarative (everything in git)
- ✅ Modern, fast, secure protocol
- ✅ Easy to add/remove clients
- ✅ Battery-efficient on mobile
- ✅ Deploy with `./deploy_remote vps` and `./deploy_remote pi`

**Trade-offs:**
- ❌ Requires WireGuard app (not native VPN)
- ❌ Different protocol than StrongSwan/IKEv2

This is the **recommended approach** if you don't specifically need IKEv2/IPsec compatibility!
