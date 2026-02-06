#!/usr/bin/env bash

set -euo pipefail

# Default values
SECRETS_DIR="/mnt/pegasus/secrets/wireguard"
CONFIG_DIR=""
ROUTE_ALL_TRAFFIC=false
CONFIG_NAME=""
IP_SUFFIX=""
NO_AGENIX=false
AGENIX_PATH="./secrets"
AGENIX_KEY="/mnt/pegasus/secrets/agenix/agenix-hosts"
HOST=""

# VPS settings
VPS_PUBLIC_KEY="TnZpPk/diUblm/aQG/dm9yqFPCnfjQrZ/g5xwoAcChU="
VPS_ENDPOINT="home-gw.mingalev.net:51820"
DNS_SERVER="172.26.249.253"

# Usage function
usage() {
    cat <<EOF
Usage: $0 <host> <ip-suffix> [OPTIONS]

Generate a WireGuard client configuration.

Required Arguments:
  <host>                    Host name for agenix file and default config name
  <ip-suffix>               Last octet of IP address (10-254)
                            Will be assigned 10.100.0.<ip-suffix>

Optional Arguments:
  --config-name NAME        Config name (default: <host>-h for home network, <host>-g for all traffic)
                            Must be 15 characters or less for Android compatibility
  --secrets-dir DIR         Directory to store keys (default: /mnt/pegasus/secrets/wireguard/)
  --config-dir DIR          Directory to store config files (default: \${secrets-dir}/configs/)
  --route-all-traffic       Route all traffic through VPN (default: home network only)
  --agenix-path DIR         Directory for agenix encrypted files (default: ./secrets)
  --agenix-key FILE         Agenix private key file (default: /mnt/pegasus/secrets/agenix/agenix-hosts)
  --no-agenix               Don't generate agenix encrypted private key
  -h, --help                Show this help message

Examples:
  # Generate home network only config with IP 10.100.0.20 (creates alice-h.conf)
  $0 alice 20

  # Generate full VPN config with IP 10.100.0.30 (creates bob-g.conf)
  $0 bob 30 --route-all-traffic

  # Custom config name
  $0 charlie 40 --config-name charlie-vpn --route-all-traffic

  # Custom directories
  $0 dave 50 --secrets-dir /tmp/wg --config-dir /tmp/wg/configs

Current IP assignments:
  10 - pixel10
  11 - igor
  12 - tanya
EOF
    exit 1
}

# Parse arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        --config-name)
            CONFIG_NAME="$2"
            shift 2
            ;;
        --secrets-dir)
            SECRETS_DIR="$2"
            shift 2
            ;;
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --route-all-traffic)
            ROUTE_ALL_TRAFFIC=true
            shift
            ;;
        --agenix-path)
            AGENIX_PATH="$2"
            shift 2
            ;;
        --agenix-key)
            AGENIX_KEY="$2"
            shift 2
            ;;
        --no-agenix)
            NO_AGENIX=true
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Validate positional arguments
if [[ ${#POSITIONAL_ARGS[@]} -lt 2 ]]; then
    echo "Error: Host name and IP suffix are required" >&2
    usage
fi

if [[ ${#POSITIONAL_ARGS[@]} -gt 2 ]]; then
    echo "Error: Too many arguments" >&2
    usage
fi

HOST="${POSITIONAL_ARGS[0]}"
IP_SUFFIX="${POSITIONAL_ARGS[1]}"

# Validate host
if [[ -z "$HOST" ]]; then
    echo "Error: Host name is required" >&2
    usage
fi

# Set default config name based on routing mode if not provided
if [[ -z "$CONFIG_NAME" ]]; then
    if [[ "$ROUTE_ALL_TRAFFIC" == true ]]; then
        CONFIG_NAME="${HOST}-g"
    else
        CONFIG_NAME="${HOST}-h"
    fi
fi

# Validate config name length (15 chars max for Android WireGuard)
if [[ ${#CONFIG_NAME} -gt 15 ]]; then
    echo "Error: Config name '$CONFIG_NAME' is too long (${#CONFIG_NAME} chars)" >&2
    echo "       Android WireGuard requires 15 characters or less" >&2
    exit 1
fi

# Validate IP suffix
if ! [[ "$IP_SUFFIX" =~ ^[0-9]+$ ]]; then
    echo "Error: IP suffix must be a number" >&2
    exit 1
fi

if [[ "$IP_SUFFIX" -lt 10 ]] || [[ "$IP_SUFFIX" -gt 254 ]]; then
    echo "Error: IP suffix must be between 10 and 254" >&2
    exit 1
fi

CLIENT_IP="10.100.0.${IP_SUFFIX}"

# Set default config dir if not provided
if [[ -z "$CONFIG_DIR" ]]; then
    CONFIG_DIR="${SECRETS_DIR}/configs"
fi

# Create directories if they don't exist
mkdir -p "$SECRETS_DIR"
mkdir -p "$CONFIG_DIR"

# File paths
PRIVATE_KEY_FILE="${SECRETS_DIR}/wireguard-${CONFIG_NAME}-private"
PUBLIC_KEY_FILE="${SECRETS_DIR}/wireguard-${CONFIG_NAME}-public"
CONFIG_FILE="${CONFIG_DIR}/${CONFIG_NAME}.conf"

# Check if keys already exist
if [[ -f "$PRIVATE_KEY_FILE" ]] || [[ -f "$PUBLIC_KEY_FILE" ]]; then
    echo "Error: Keys already exist for '$CONFIG_NAME'" >&2
    echo "       Private key: $PRIVATE_KEY_FILE" >&2
    echo "       Public key: $PUBLIC_KEY_FILE" >&2
    echo "       Remove them first if you want to regenerate" >&2
    exit 1
fi

# Check if config already exists
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file already exists: $CONFIG_FILE" >&2
    echo "       Remove it first if you want to regenerate" >&2
    exit 1
fi

# Generate keypair
echo "Generating WireGuard keypair for '$CONFIG_NAME'..."
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# Save keys
echo "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
echo "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"
chmod 644 "$PUBLIC_KEY_FILE"

echo "✓ Keys generated:"
echo "  Private key: $PRIVATE_KEY_FILE"
echo "  Public key:  $PUBLIC_KEY_FILE"
echo "✓ Assigned IP: $CLIENT_IP"

# Determine AllowedIPs based on mode
if [[ "$ROUTE_ALL_TRAFFIC" == true ]]; then
    ALLOWED_IPS="0.0.0.0/0, ::/0"
    MODE="all traffic"
else
    ALLOWED_IPS="172.26.249.0/24"
    MODE="home network only"
fi

# Generate config file
echo ""
echo "Generating config file ($MODE)..."

cat > "$CONFIG_FILE" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = ${CLIENT_IP}/24
DNS = $DNS_SERVER

[Peer]
PublicKey = $VPS_PUBLIC_KEY
Endpoint = $VPS_ENDPOINT
AllowedIPs = $ALLOWED_IPS
PersistentKeepalive = 25
EOF

echo "✓ Config file created: $CONFIG_FILE"

# Generate agenix encrypted private key if requested
AGENIX_FILE=""
if [[ "$NO_AGENIX" == false ]]; then
    echo ""
    echo "Generating agenix encrypted private key..."

    AGENIX_FILENAME="wireguard-${HOST}.age"
    AGENIX_FILE="${AGENIX_PATH}/${AGENIX_FILENAME}"

    # Create agenix directory if it doesn't exist
    mkdir -p "$AGENIX_PATH"

    # Check if agenix file already exists
    if [[ -f "$AGENIX_FILE" ]]; then
        echo "Warning: Agenix file already exists: $AGENIX_FILE" >&2
        echo "         Skipping agenix encryption. Remove it first if you want to regenerate." >&2
    else
        # Add entry to wireguard.nix before encrypting
        WIREGUARD_SECRETS_FILE="${AGENIX_PATH}/wireguard.nix"
        SECRET_NAME="${AGENIX_FILENAME}"

        # Check if entry already exists
        if ! grep -q "\"${SECRET_NAME}\"" "$WIREGUARD_SECRETS_FILE" 2>/dev/null; then
            echo "Adding ${SECRET_NAME} to ${WIREGUARD_SECRETS_FILE}..."

            # Add the new entry before the closing brace
            sed -i "/^}/i\\  \"${SECRET_NAME}\".publicKeys = [ mingaleg allHosts ];" "$WIREGUARD_SECRETS_FILE"

            echo "✓ Added to secrets configuration"
        fi

        # Encrypt the private key with agenix
        # Run from AGENIX_PATH directory so agenix finds the right entry in secrets.nix
        if ! (cd "$AGENIX_PATH" && echo "$PRIVATE_KEY" | EDITOR="tee" agenix -e "$AGENIX_FILENAME" -i "$AGENIX_KEY"); then
            echo "Error: agenix encryption failed" >&2
            echo "       Make sure agenix is installed and key file exists: $AGENIX_KEY" >&2
            echo "       You can disable agenix with --no-agenix flag" >&2
            echo "" >&2
            echo "       To encrypt manually later:" >&2
            echo "       (cd $AGENIX_PATH && cat $PRIVATE_KEY_FILE | EDITOR=\"tee\" agenix -e $AGENIX_FILENAME -i $AGENIX_KEY)" >&2
            # Clean up generated files
            rm -f "$PRIVATE_KEY_FILE" "$PUBLIC_KEY_FILE" "$CONFIG_FILE"
            exit 1
        fi

        if [[ -f "$AGENIX_FILE" ]]; then
            echo "✓ Agenix encrypted key: $AGENIX_FILE"
        fi
    fi
fi

# Print summary
echo ""
echo "========================================="
echo "WireGuard Configuration Summary"
echo "========================================="
echo "Config name:     $CONFIG_NAME"
echo "Host name:       $HOST"
echo "Client IP:       $CLIENT_IP/24"
echo "DNS server:      $DNS_SERVER"
echo "VPS endpoint:    $VPS_ENDPOINT"
echo "Routing mode:    $MODE"
echo "Public key:      $PUBLIC_KEY"
if [[ -n "$AGENIX_FILE" && -f "$AGENIX_FILE" ]]; then
    echo "Agenix file:     $AGENIX_FILE"
fi
echo ""
echo "Next steps:"
echo "1. Add this peer to hosts/vps/wireguard.nix:"
echo ""
echo "   {"
echo "     # ${HOST}"
echo "     publicKey = \"$PUBLIC_KEY\";"
echo "     allowedIPs = [ \"${CLIENT_IP}/32\" ];"
echo "   }"
echo ""
if [[ -n "$AGENIX_FILE" && -f "$AGENIX_FILE" ]]; then
    echo "2. Add agenix secret to hosts/${HOST}/wireguard.nix (or similar):"
    echo ""
    echo "   age.secrets.wireguard-${HOST}-private = {"
    echo "     file = ../../secrets/wireguard-${HOST}.age;"
    echo "     owner = \"root\";"
    echo "     group = \"systemd-network\";"
    echo "     mode = \"0440\";"
    echo "   };"
    echo ""
    echo "3. Deploy to VPS:"
else
    echo "2. Deploy to VPS:"
fi
echo "   ./deploy_remote vps"
echo ""
if [[ -n "$AGENIX_FILE" && -f "$AGENIX_FILE" ]]; then
    echo "4. Import config on client device:"
else
    echo "3. Import config on client device:"
fi
echo "   $CONFIG_FILE"
echo "========================================="
