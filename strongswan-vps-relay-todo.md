# StrongSwan VPN via GCP NixOS VPS Relay

## ⚠️ ISSUES FOUND - READ BEFORE PROCEEDING

### Critical Issues

**1. Google Cloud SDK Not Installed Locally**
- Status: gcloud CLI not found in PATH on local machine (minganix/mingamini)
- Impact: Cannot create GCP resources (VM, firewall, storage bucket)
- Fix: Install google-cloud-sdk on local machine OR run gcloud commands from Pi
- Note: Pi's strongswan.nix uses ${pkgs.google-cloud-sdk} but it's not in user PATH

**2. WireGuard Tools Not Available**
- Status: `wg` command not found locally
- Impact: Cannot generate WireGuard keypairs
- Fix: Install wireguard-tools package locally OR generate keys on Pi

**3. VPS Hostname Resolution for Deployment**
- Status: deploy_remote script uses `--target-host ${HOST}` expecting hostname "vps"
- Impact: SSH to "vps" will fail (no DNS/hosts entry)
- Fix Options:
  a) Add VPS IP to /etc/hosts: `<VPS_IP> vps`
  b) Add to ~/.ssh/config with ProxyJump if needed
  c) Modify deploy_remote to accept IPs
- Recommended: Use SSH config with proper hostname

**4. DNS Update Service Conflict**
- Status: Pi runs update-home-dns timer every 5min, sets DNS to home IP (185.241.165.36)
- Impact: After setting DNS to VPS IP, Pi will overwrite it back to home IP
- Fix: Comment out or remove update-home-dns service from hosts/pi/strongswan.nix (declarative)
- Handled in: Part 4 Step 3

### Configuration Issues

**5. VPS Initial Bootstrap Problem**
- Status: Guide shows deploying with `./deploy_remote vps` but new GCP VM has default NixOS
- Impact: Cannot deploy our config to unconfigured VM
- Fix Needed: Add bootstrap steps to:
  - Copy flake to VM
  - Initial nixos-rebuild on VM
  - OR configure VM to pull config from git

**6. Network Interface Name Assumption**
- Status: iptables rules assume interface "ens4"
- GCP Default: Usually ens4, but depends on instance type
- Risk: Rules will fail silently if interface is different (eth0, enp0s3, etc.)
- Fix: Add verification step OR make interface configurable

**7. Missing Module Import in VPS Config**
- Status: VPS config sets `virtualisation.googleComputeImage.enable = true`
- Issue: google-compute-image.nix module not imported anywhere
- Impact: Option may not exist, causing build failure
- Fix: Import from nixpkgs modulesPath: `"${modulesPath}/virtualisation/google-compute-image.nix"`

**8. GCP Image Upload Process**
- Status: Guide suggests downloading pre-built NixOS GCP image
- Risk: nixos.org may not have 25.11 GCP image yet (stable recently released)
- Alternative: Build locally with nix-build (slower but reliable)
- Should verify image availability before proceeding

### Security/Operational Issues

**9. No Static IP Reservation**
- Status: VM created with ephemeral IP
- Risk: VPS IP changes on restart, breaks DNS and Pi's WireGuard endpoint
- Fix: Reserve static IP with `gcloud compute addresses create`
- Cost: $3/month but essential for this setup

**10. No Monitoring/Alerting**
- Status: If WireGuard tunnel goes down, no notification
- Impact: VPN breaks silently until manually checked
- Enhancement: Add systemd path/timer to monitor tunnel health

**11. Firewall Rules Order**
- Status: Guide creates firewall rules before VM
- Issue: Not a problem (rules can exist without targets), but could be clearer
- Tags are applied to VM, rules filter by tags

### Minor Issues

**12. GCP Region Not Discussed**
- Guide uses: europe-west2-a
- Should verify: User's preferred region (latency, cost varies)
- London-based user: europe-west2 (London) is good choice

**13. Missing Cost Breakdown for Static IP**
- Guide shows ~$10-13/month but doesn't break down static IP cost
- Static IP: ~$3/month (essential for this setup)

**14. WireGuard Key Security**
- Status: Keys will be in secrets/*.age (encrypted)
- Good: Using agenix for encryption
- Note: After generating, delete plaintext keys from disk

**15. Major Workflow/Ordering Issues**
- **CRITICAL**: Guide has config files with placeholders (PI_PUBLIC_KEY_HERE, VPS_PUBLIC_IP)
- Problem: Part 5 bootstrap tries to build VPS config with placeholders - WILL FAIL
- Problem: Agenix key deployed AFTER bootstrap but config needs it DURING bootstrap
- Problem: No step to replace placeholders with actual values before building
- Fix: Reorder steps - generate keys first, create configs with real values, THEN bootstrap

**16. SSH Key Path Mismatch**
- **CRITICAL**: SSH config uses `IdentityFile ~/.ssh/id_ed25519`
- Reality: VM created with `ssh-keys/mingaleg-masterkey.pub`
- Impact: SSH authentication will FAIL
- Fix: Use correct identity file path

**17. Missing Variable Definitions**
- Part 6 step 1 uses `$VPS_PUBLIC_IP` but variable not set
- Part 7 uses `VPS_PUBLIC_IP` in multiple places
- Should define it consistently or use `vps` hostname from SSH config

**18. No Local Build Verification**
- Guide doesn't say to test-build configs locally before deploying
- Risk: Deploy broken config to VPS/Pi, harder to debug remotely
- Fix: Add `nix build .#nixosConfigurations.vps.config.system.build.toplevel` step

**19. Incomplete Bootstrap Process**
- Part 5 bootstrap moves config to `/etc/nixos` (overwrites existing)
- Part 5 bootstrap won't work if agenix secrets referenced but key not deployed
- Should: Deploy agenix key BEFORE bootstrap, or bootstrap without secrets first

**20. Missing Commit/Save Steps**
- Guide says "Create file X" but doesn't say to save changes
- `deploy_remote` uses local flake - unsaved changes won't deploy
- Fix: Add explicit save/commit steps after creating config files

**21. Maintenance Command Incorrect**
- Says: `sudo systemctl restart wg-quick@wg0`
- Reality: NixOS uses systemd-networkd for wireguard.interfaces, not wg-quick
- Fix: Should be `sudo systemctl restart systemd-networkd`

**22. No Plaintext Key Cleanup**
- Part 2 mentions deleting plaintext keys but no command provided
- Security risk if forgotten
- Fix: Add explicit `rm wireguard-*-private wireguard-*-public` step

**23. Verification Order Wrong**
- Part 6 step 4: Update DNS
- Part 7: Verify WireGuard tunnel
- Problem: Should verify tunnel BEFORE updating DNS
- If tunnel broken, DNS points to VPS but VPN doesn't work

**24. Router Port Forwarding Now Unused**
- Pi's router has UDP 500/4500 forwarding configured
- With VPS relay, this is no longer used
- Should mention: Can remove router port forwarding (or leave it, harmless)

---

## Overview

Since your ISP uses CGNAT, you cannot receive inbound connections directly. This solution uses a GCP VM running NixOS as a relay:

```
VPN Client → GCP VPS (public IP) → WireGuard Tunnel → Pi (StrongSwan)
```

**Architecture:**
- GCP VPS runs NixOS, managed declaratively like your Pi
- Permanent WireGuard tunnel: Pi ↔ VPS
- VPS forwards UDP 500/4500 traffic through WireGuard to Pi
- Pi handles StrongSwan VPN authentication and routing
- VPN clients connect to VPS's public IP
- Deploy with `./deploy_remote vps` just like the Pi

**Cost:** ~$5-10/month for e2-micro instance

---

## Before You Begin

### Required Tools (Install First)

Enter a nix shell with required tools:

```bash
nix-shell -p google-cloud-sdk wireguard-tools
```

Then authenticate with Google Cloud:

```bash
gcloud auth login
gcloud config set project mingaleg
```

### Reserve Static IP (Do This First)

Reserve a static IP for the VPS **before** creating the VM:

```bash
gcloud compute addresses create vps-static-ip \
  --region=europe-west2 \
  --project=mingaleg

# Verify it was created:
gcloud compute addresses describe vps-static-ip \
  --region=europe-west2 \
  --format='get(address)'
```

This IP will be attached to the VM in Part 1 Step 4.

---

## Prerequisites & Critical Notes

**Prerequisites:**
- GCP account (you already have one from DNS setup)
- Your existing StrongSwan configuration (already complete)
- Google Cloud SDK installed and authenticated (see fixes above)
- WireGuard tools installed (see fixes above)
- SSH access to Pi (already have)

**CRITICAL WORKFLOW NOTES:**
1. **Generate keys FIRST**, then create configs with actual values (no placeholders)
2. **Test build locally** before deploying to remote hosts
3. **Deploy agenix key BEFORE bootstrap** so secrets can be decrypted
4. **Verify tunnel works BEFORE updating DNS** to avoid downtime
5. **Use correct SSH key path** in SSH config (mingaleg-masterkey, not id_ed25519)
6. **Export and reuse VPS_IP variable** throughout the process
7. **Delete plaintext WireGuard keys** after encrypting to *.age files

---

## Part 1: Build & Upload NixOS Image to GCP

NixOS provides a GCP image builder. We'll build an image and upload it to your GCP project.

### 1. Build NixOS GCP Image

```bash
# On your local machine
nix-build '<nixpkgs/nixos>' -A config.system.build.googleComputeImage \
  --arg configuration "{ modulesPath, ... }: { imports = [ \"\${modulesPath}/virtualisation/google-compute-image.nix\" ]; }"
```

This creates a `.tar.gz` image in `./result/`.

**Alternative (faster):** Use pre-built NixOS GCP images from the community:

```bash
# Download latest NixOS 25.11 GCP image
curl -L https://nixos.org/channels/nixos-25.11/latest-nixos-gce.tar.gz -o nixos-gce.tar.gz
```

### 2. Upload Image to Google Cloud Storage

```bash
# Create a bucket for the image (one-time)
gsutil mb -p mingaleg -l europe-west2 gs://nixos-images-mingaleg

# Upload the image
gsutil cp nixos-gce.tar.gz gs://nixos-images-mingaleg/

# Or if you built it yourself:
# gsutil cp ./result/*.tar.gz gs://nixos-images-mingaleg/nixos-gce.tar.gz
```

### 3. Create GCP Image from Upload

```bash
gcloud compute images create nixos-25-11 \
  --source-uri gs://nixos-images-mingaleg/nixos-gce.tar.gz \
  --family nixos \
  --description "NixOS 25.11 for GCE"
```

### 4. Create VM from NixOS Image

**IMPORTANT:** Use the static IP created earlier to avoid IP changes on reboot.

```bash
gcloud compute instances create vps \
  --zone=europe-west2-a \
  --machine-type=e2-micro \
  --image=nixos-25-11 \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-standard \
  --tags=vps-relay \
  --address=vps-static-ip \
  --metadata=ssh-keys="mingaleg:$(cat ssh-keys/mingaleg-masterkey.pub)"
```

**Note:**
- Uses your existing SSH key for access
- `--address=vps-static-ip` attaches the reserved static IP
- Static IP persists across VM restarts/recreates

### 5. Create Firewall Rules

```bash
# Allow UDP 500 and 4500 for IPsec
gcloud compute firewall-rules create vps-ipsec \
  --allow=udp:500,udp:4500 \
  --target-tags=vps-relay \
  --description="Allow IPsec VPN traffic"

# Allow WireGuard
gcloud compute firewall-rules create vps-wireguard \
  --allow=udp:51820 \
  --target-tags=vps-relay \
  --description="Allow WireGuard tunnel"

# Allow SSH
gcloud compute firewall-rules create vps-ssh \
  --allow=tcp:22 \
  --target-tags=vps-relay \
  --description="Allow SSH"
```

---

## Part 2: Generate WireGuard Keys & Get VPS IP

### 1. Get and Save VPS Static IP

```bash
# Get the VPS static IP and save to variable
export VPS_IP=$(gcloud compute addresses describe vps-static-ip \
  --region=europe-west2 --format='get(address)')
echo "VPS IP: $VPS_IP"

# Save to file for later reference
echo "$VPS_IP" > vps-ip.txt
```

**IMPORTANT**: You'll need this IP for Pi configuration. Keep this terminal open or save the IP.

### 2. Generate Keys Locally

On your local machine (in nix-shell -p wireguard-tools):

```bash
# VPS keys
wg genkey > wireguard-vps-private
wg pubkey < wireguard-vps-private > wireguard-vps-public

# Pi keys
wg genkey > wireguard-pi-private
wg pubkey < wireguard-pi-private > wireguard-pi-public

# Display and save keys for configuration
echo "=== VPS Keys ==="
echo "Private:"
cat wireguard-vps-private
echo "Public:"
export VPS_PUBLIC_KEY=$(cat wireguard-vps-public)
echo "$VPS_PUBLIC_KEY"

echo ""
echo "=== Pi Keys ==="
echo "Private:"
cat wireguard-pi-private
echo "Public:"
export PI_PUBLIC_KEY=$(cat wireguard-pi-public)
echo "$PI_PUBLIC_KEY"

echo ""
echo "Copy these values - you'll need them for the next steps"

# Save to a temporary script in case terminal session ends
cat > /tmp/wg-vars.sh <<VARS
export VPS_IP="$VPS_IP"
export VPS_PUBLIC_KEY="$VPS_PUBLIC_KEY"
export PI_PUBLIC_KEY="$PI_PUBLIC_KEY"
VARS
chmod 600 /tmp/wg-vars.sh
echo "Variables saved to /tmp/wg-vars.sh (run 'source /tmp/wg-vars.sh' if session ends)"
```

**Save these exported variables** - you'll use them when creating config files.

**If your terminal session ends**, reload variables with:
```bash
source /tmp/wg-vars.sh
```

### 3. Add Keys to Secrets

Update `secrets/secrets.nix`:

```nix
{
  "vpn-users.age".publicKeys = [ mingaleg allHosts ];
  "gcp-dns-credentials.age".publicKeys = [ mingaleg allHosts ];
  "wireguard-pi-private.age".publicKeys = [ mingaleg allHosts ];
  "wireguard-vps-private.age".publicKeys = [ mingaleg allHosts ];
}
```

Encrypt the keys:

```bash
cd secrets
cat ../wireguard-pi-private | EDITOR="tee" agenix -e wireguard-pi-private.age -i ../ssh-keys/agenix-hosts
cat ../wireguard-vps-private | EDITOR="tee" agenix -e wireguard-vps-private.age -i ../ssh-keys/agenix-hosts
cd ..
```

### 4. Delete Plaintext Keys

**CRITICAL SECURITY STEP**: Delete plaintext keys now that they're encrypted:

```bash
# Delete private keys (sensitive)
rm -f wireguard-vps-private wireguard-pi-private

# Keep public keys and VPS IP temporarily for config creation
# We'll delete them after creating config files
echo "Private keys deleted. Public keys and VPS IP saved for config creation."
```

**Note**: Public keys and VPS IP are exported to shell variables. We'll delete the files after creating configs.

---

## Part 3: Create VPS NixOS Configuration

### 1. Create VPS Configuration File

Create directory and configuration file:

```bash
mkdir -p hosts/vps

cat > hosts/vps/default.nix <<'EOF'
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
    ./wireguard-relay.nix
  ];

  networking.hostName = "vps";

  # Google Compute Engine is configured via imported module above

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
  ];

  # Enable IP forwarding for relay
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
EOF
```

**Note**: Using single quotes `'EOF'` prevents variable expansion in this file (no variables needed).

### 2. Create WireGuard Relay Configuration

Create WireGuard relay configuration file.

**IMPORTANT**: Use the **Pi's public key** from the exported `$PI_PUBLIC_KEY` variable:

```bash
# If terminal session ended, reload variables first:
# source /tmp/wg-vars.sh

cat > hosts/vps/wireguard-relay.nix <<EOF
{ config, pkgs, ... }:

{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-vps-private = {
    file = ../../secrets/wireguard-vps-private.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.200.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;

      peers = [
        {
          # Pi
          publicKey = "$PI_PUBLIC_KEY";
          allowedIPs = [ "10.200.0.2/32" ];
          persistentKeepalive = 25;
        }
      ];

      # NAT configuration for forwarding IPsec traffic to Pi
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ens4 -p udp --dport 500 -j DNAT --to-destination 10.200.0.2:500
        ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ens4 -p udp --dport 4500 -j DNAT --to-destination 10.200.0.2:4500
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
      '';

      postShutdown = ''
        \${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ens4 -p udp --dport 500 -j DNAT --to-destination 10.200.0.2:500
        \${pkgs.iptables}/bin/iptables -t nat -D PREROUTING -i ens4 -p udp --dport 4500 -j DNAT --to-destination 10.200.0.2:4500
        \${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE
        \${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
        \${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
      '';
    };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedUDPPorts = [ 500 4500 51820 ];
    allowedTCPPorts = [ 22 ];
  };
}
EOF
```

**Note**: The file now contains the actual Pi public key (no placeholders).

### 3. Add VPS to Flake

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

  # Add VPS configuration
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

## Part 4: Configure WireGuard on Pi

### 1. Create Pi WireGuard Relay Configuration

Create WireGuard relay configuration file.

**IMPORTANT**: Use the **VPS public key** and **VPS IP** from exported variables:

```bash
# If terminal session ended, reload variables first:
# source /tmp/wg-vars.sh

cat > hosts/pi/wireguard-relay.nix <<EOF
{ config, pkgs, ... }:

{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-pi-private = {
    file = ../../secrets/wireguard-pi-private.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.200.0.2/24" ];
      listenPort = 51820;
      privateKeyFile = config.age.secrets.wireguard-pi-private.path;

      peers = [
        {
          # GCP VPS
          publicKey = "$VPS_PUBLIC_KEY";
          allowedIPs = [ "10.200.0.1/32" ];
          endpoint = "$VPS_IP:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };

  # Open WireGuard port
  networking.firewall.allowedUDPPorts = [ 51820 ];
}
EOF
```

**Note**: The file now contains actual VPS public key and IP (no placeholders).

### 2. Import Module and Disable DNS Updates

In `hosts/pi/default.nix`, add to imports:

```nix
imports = [
  ./hardware-configuration.nix
  ./samba-server.nix
  ./pihole.nix
  ./strongswan.nix
  ./wireguard-relay.nix  # Add this
];
```

### 3. Disable Dynamic DNS Update Service

Since DNS will now point to VPS static IP (not home IP), disable the dynamic DNS updater.

Edit `hosts/pi/strongswan.nix` and comment out or remove the entire DNS update service and timer:

**Option A: Comment out (recommended - easy to re-enable later):**

Find these sections and comment them out:
```nix
  # Dynamic DNS update service - DISABLED (using VPS relay)
  # systemd.services.update-home-dns = { ... };
  # systemd.timers.update-home-dns = { ... };
```

**Option B: Remove entirely** - delete lines 123-174 (the entire update-home-dns service and timer)

After this change, the Pi will no longer update DNS records automatically.

### 4. Test Build Locally

**CRITICAL**: Test building both configs locally before proceeding:

```bash
# Test VPS build
echo "Testing VPS configuration build..."
nix build .#nixosConfigurations.vps.config.system.build.toplevel

# Test Pi build
echo "Testing Pi configuration build..."
nix build .#nixosConfigurations.pi.config.system.build.toplevel

echo "Both configurations build successfully!"
```

If either build fails, fix the errors before proceeding. Common issues:
- Missing module imports
- Syntax errors in nix files
- Invalid public keys (wrong format)

### 5. Clean Up Remaining Plaintext Files

Now that configs are created and tested, delete remaining plaintext files:

```bash
rm -f wireguard-vps-public wireguard-pi-public vps-ip.txt /tmp/wg-vars.sh
echo "All plaintext WireGuard files deleted. Only encrypted *.age files remain."
```

---

## Part 5: Bootstrap VPS with Initial Configuration

The newly created GCP VM runs default NixOS. We need to bootstrap it with our configuration.

### Option A: Remote Bootstrap (Recommended)

1. **Get VPS IP (if not already exported)**
   ```bash
   export VPS_IP=$(gcloud compute addresses describe vps-static-ip \
     --region=europe-west2 --format='get(address)')
   echo "VPS IP: $VPS_IP"
   ```

2. **Add VPS to SSH Config**

   **IMPORTANT**: Use the correct SSH key path (find it first):

   ```bash
   # Find your actual private key
   ls -la ssh-keys/mingaleg-masterkey*

   # Add to SSH config with full path
   cat >> ~/.ssh/config <<EOF
   Host vps
     HostName $VPS_IP
     User mingaleg
     IdentityFile $(pwd)/ssh-keys/mingaleg-masterkey
   EOF
   ```

3. **Test SSH Access**
   ```bash
   ssh vps 'echo "SSH to VPS working!"'
   ```

   If this fails, check:
   - Key path is correct
   - Key permissions (should be 600)
   - VPS firewall allows SSH (should be configured)

4. **Check Network Interface Name**
   ```bash
   ssh vps 'ip -br addr show'
   ```
   **Verify the interface name** (should be ens4). If different, update `hosts/vps/wireguard-relay.nix` iptables rules (change ens4 to actual interface).

5. **Deploy Agenix Private Key FIRST**

   **CRITICAL**: Must deploy before bootstrap so secrets can be decrypted:

   ```bash
   scp ssh-keys/agenix-hosts vps:/tmp/
   ssh vps 'sudo mkdir -p /root/.ssh && \
     sudo mv /tmp/agenix-hosts /root/.ssh/ && \
     sudo chmod 600 /root/.ssh/agenix-hosts && \
     sudo chown root:root /root/.ssh/agenix-hosts'

   # Verify deployed
   ssh vps 'sudo ls -la /root/.ssh/agenix-hosts'
   ```

6. **Copy Flake to VPS**
   ```bash
   # Copy entire config to VPS
   rsync -avz --exclude='.git' --exclude='result' \
     $(pwd)/ vps:/tmp/nixos-config/
   ```

7. **Initial Build on VPS**
   ```bash
   ssh vps 'sudo mv /tmp/nixos-config /etc/nixos && \
     cd /etc/nixos && \
     sudo nixos-rebuild switch --flake .#vps'
   ```

   This will:
   - Apply VPS configuration
   - Enable WireGuard interface
   - Set up iptables forwarding rules
   - Configure firewall

### Option B: Manual Configuration (If Option A Fails)

If the remote bootstrap fails (missing nix-command, etc.):

1. SSH to VPS
2. Enable flakes manually in `/etc/nixos/configuration.nix`
3. Copy configuration files manually
4. Run nixos-rebuild

---

## Part 6: Deploy Configuration Updates

### 1. Deploy Updated VPS Configuration (if needed)

The VPS was already configured in Part 5. If you make any config changes later:

```bash
./deploy_remote vps
```

**Note:** This works because:
- VPS has our flake at /etc/nixos
- SSH config has "vps" hostname pointing to static IP
- Agenix key is deployed at /root/.ssh/agenix-hosts
- deploy_remote uses `--target-host vps` which resolves via SSH config

### 2. Deploy Pi Configuration

Update Pi with WireGuard tunnel configuration and disabled DNS updater:

```bash
./deploy_remote pi
```

**Verify deployment:**
```bash
# Check WireGuard interface exists
ssh mingaleg@pi 'ip addr show wg0'

# Verify DNS update service is disabled/removed
ssh mingaleg@pi 'sudo systemctl status update-home-dns.timer'
# Should show: Unit update-home-dns.timer could not be found (if removed)
# Or: inactive/disabled (if commented out)
```

---

## Part 7: Verify Tunnel BEFORE Updating DNS

**CRITICAL**: Verify WireGuard tunnel works before updating DNS!

### 1. Check WireGuard Tunnel Status

**On VPS:**
```bash
ssh vps 'sudo wg show'
```

Should show:
- Interface `wg0` with private key
- Peer (Pi) with **recent handshake timestamp** (e.g., "1 minute ago")
- Received/sent bytes > 0

**On Pi:**
```bash
ssh mingaleg@pi 'sudo wg show'
```

Should show:
- Interface `wg0` with private key
- Peer (VPS) with **recent handshake timestamp** and **endpoint** showing VPS IP
- Received/sent bytes > 0

### 2. Test Tunnel Connectivity

**From VPS, ping Pi through tunnel:**
```bash
ssh vps 'ping -c 3 10.200.0.2'
```

**From Pi, ping VPS through tunnel:**
```bash
ssh mingaleg@pi 'ping -c 3 10.200.0.1'
```

Both should succeed. If they fail, DO NOT proceed to DNS update - troubleshoot first.

### 3. Test Port Forwarding

**On Pi, start tcpdump:**
```bash
ssh mingaleg@pi 'sudo tcpdump -i wg0 -n "udp port 500 or udp port 4500"'
```

Keep this running in a separate terminal.

**On VPS, test forwarding:**
```bash
# Send a test UDP packet to VPS IPsec port, should appear on Pi's wg0
ssh vps 'echo "test" | nc -u -w1 $(hostname -I | awk "{print \$1}") 500'
```

You should see packets on Pi's tcpdump.

### 4. Update DNS to Point to VPS

**Only proceed if tunnel and forwarding work!**

```bash
# Get VPS IP (if variable not set)
export VPS_IP=$(gcloud compute addresses describe vps-static-ip \
  --region=europe-west2 --format='get(address)')

echo "Updating DNS from current IP to VPS IP: $VPS_IP"

gcloud dns record-sets update home.mingalev.net. \
  --rrdatas="$VPS_IP" \
  --type=A \
  --ttl=300 \
  --zone="mingalev-net" \
  --project="mingaleg"
```

**Verify DNS propagation:**
```bash
dig +short home.mingalev.net
# Should show VPS static IP (not old home IP 185.241.165.36)
```

**Note:** The Pi's DNS update service was disabled, so this change is permanent.

---

## Part 8: Test End-to-End VPN Connection

### 1. Test from VPN Client

**Prerequisites:**
- DNS has been updated to VPS IP
- WireGuard tunnel is established and working

**On Android StrongSwan App:**
1. Ensure on mobile data (not home WiFi)
2. Server: `home.mingalev.net`
3. Certificate: Download from VPS or use automatic (Let's Encrypt should be trusted)
4. Username: `mingaleg`
5. Password: (your VPN password from vpn-users.age)
6. Connect

**On Pi, monitor StrongSwan:**
```bash
ssh mingaleg@pi 'sudo journalctl -fu strongswan-swanctl'
```

You should see:
- IKE_SA connection established
- EAP authentication successful
- Client assigned IP from pool (172.26.249.161-174)

### 2. Verify VPN Traffic Flow

**Check tcpdump on Pi's WireGuard interface:**
```bash
ssh mingaleg@pi 'sudo tcpdump -i wg0 -n "udp port 500 or udp port 4500"'
```

Should see IPsec traffic from VPS (10.200.0.1) being forwarded.

### 3. Test VPN Functionality

Once connected:
- Ping home network device: `ping 172.26.249.253` (Pi)
- Access Pi-hole admin: `http://172.26.249.253/admin`
- DNS queries should go through Pi-hole
- All traffic routes through VPN

### Expected Flow

```
Android Client (185.x.x.x:random)
  → VPS Public IP (UDP 500/4500)
    → VPS WireGuard (10.200.0.1)
      → Pi WireGuard (10.200.0.2)
        → Pi StrongSwan (172.26.249.253)
          → Authenticate & assign IP from pool
            → Client gets 172.26.249.161-174
              → Traffic routes through Pi
```

### Troubleshooting

**WireGuard tunnel not establishing:**
- Check firewall rules on GCP (UDP 51820 should be allowed)
- Verify public keys match in both configs (check files: hosts/vps/wireguard-relay.nix and hosts/pi/wireguard-relay.nix)
- Check VPS logs: `ssh vps 'sudo journalctl -u systemd-networkd | grep wg0'`
- Check Pi logs: `ssh mingaleg@pi 'sudo journalctl -u systemd-networkd | grep wg0'`
- Verify VPS endpoint is reachable from Pi: `ssh mingaleg@pi "ping -c 3 $VPS_IP"`
- Check if WireGuard port is open: `ssh mingaleg@pi "nc -zvu $VPS_IP 51820"`

**VPN packets not reaching Pi:**
- Check iptables rules on VPS: `ssh vps 'sudo iptables -t nat -L -n -v'`
- Verify DNAT rules are active
- Check tcpdump on VPS: `ssh vps 'sudo tcpdump -i ens4 udp port 500'`
- Verify WireGuard is forwarding: `ssh vps 'sudo tcpdump -i wg0'`

**VPN authentication fails:**
- Check StrongSwan logs: `ssh mingaleg@pi 'sudo journalctl -u strongswan-swanctl'`
- Verify certificates are valid: `ssh mingaleg@pi 'sudo ls -la /var/lib/acme/home.mingalev.net/'`
- Check EAP credentials are loaded: `ssh mingaleg@pi 'sudo journalctl -u strongswan-swanctl | grep eap'`

### 4. Router Port Forwarding (Optional Cleanup)

Your router still has UDP 500/4500 port forwarding configured from the original setup. These are no longer needed since traffic goes through VPS.

**Optional**: Remove port forwarding rules from router (or leave them, they're harmless).

---

## Managing the VPS with NixOS

Your VPS is now fully managed with NixOS, just like your Pi!

**Deploy configuration changes:**
```bash
./deploy_remote vps
```

**Update system:**
```bash
# Update flake inputs
nix flake update

# Deploy updates
./deploy_remote vps
./deploy_remote pi
```

**View logs:**
```bash
ssh vps 'sudo journalctl -f'
```

**Rebuild on VPS directly (if needed):**
```bash
ssh vps
sudo nixos-rebuild switch --flake /etc/nixos#vps
```

---

## Costs

**GCP e2-micro VM:**
- Compute: ~$7/month
- Network egress: ~$1-3/month (depends on VPN usage)
- Static IP (if needed): $3/month
- **Total: ~$10-13/month**

**Cheaper alternatives:**
- Oracle Cloud Free Tier (1 AMD e2-micro free forever)
- Hetzner Cloud (€3.79/month for CX11)
- DigitalOcean ($6/month for basic droplet)

---

## Maintenance

### Keep WireGuard Running

Both VPS and Pi will auto-start WireGuard on boot.

If tunnel goes down, restart networking (NixOS uses systemd-networkd for wireguard.interfaces):
```bash
# On VPS
ssh vps 'sudo systemctl restart systemd-networkd'

# On Pi
ssh mingaleg@pi 'sudo systemctl restart systemd-networkd'

# Check tunnel status
ssh vps 'sudo wg show'
ssh mingaleg@pi 'sudo wg show'
```

### Monitor Tunnel Health

Add to Pi's cron or systemd timer to alert if tunnel is down:

```bash
ping -c 1 10.200.0.1 || echo "VPS tunnel down!" | mail -s "WireGuard Alert" your@email.com
```

---

## Security Notes

1. **WireGuard keys:** Treat like passwords - rotate periodically
2. **VPS access:** Password SSH disabled, uses your SSH key only
3. **GCP firewall:** Only open necessary ports (22, 500, 4500, 51820)
4. **Pi security:** Tunnel traffic is encrypted by WireGuard
5. **Updates:** Managed via NixOS flake updates - `nix flake update && ./deploy_remote vps`
6. **Agenix secrets:** Private WireGuard keys stored encrypted in git

---

## Summary

**What you've built:**
```
┌─────────────────┐
│  VPN Client     │ (Android, iOS, laptop)
│  anywhere in    │
│  the world      │
└────────┬────────┘
         │
         │ UDP 500/4500 (IKEv2/IPsec)
         │
         ▼
┌─────────────────┐
│  GCP VPS        │ Public IP, NixOS-managed
│  (NixOS)        │ ./deploy_remote vps
└────────┬────────┘
         │
         │ WireGuard tunnel (encrypted)
         │ 10.200.0.1 ↔ 10.200.0.2
         ▼
┌─────────────────┐
│  Pi             │ Behind CGNAT, NixOS-managed
│  (NixOS)        │ ./deploy_remote pi
│                 │
│  StrongSwan     │ Handles VPN auth
│  Pi-hole        │ DNS filtering
│  Samba          │ File sharing
└─────────────────┘
         │
         │
         ▼
    Home Network
    (All devices accessible)
```

**Benefits:**
- ✅ Fully declarative infrastructure (everything in git)
- ✅ Deploy with one command
- ✅ Bypasses CGNAT limitation
- ✅ Uses your existing StrongSwan config
- ✅ VPS and Pi managed identically
- ✅ Encrypted tunnel between VPS and Pi
- ✅ Low cost (~$10/month for VPS)

**Next steps:**
Follow this guide step-by-step to set up the VPS relay and restore VPN functionality!
