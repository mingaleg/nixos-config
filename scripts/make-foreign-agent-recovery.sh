#!/usr/bin/env bash

set -euo pipefail

# Writes the foreign-agent break-glass recovery stick (see foreign-agent.md):
# the foreign-agent-recovery image, plus foreign-agent's SSH host key (its
# agenix identity) copied to /recovery on the stick - never via the nix store.

SECRETS_DIR="${FA_SECRETS_DIR:-/mnt/pegasus/secrets/foreign-agent}"
IMAGE=""

usage() {
    cat <<EOF
Usage: $0 [--image <path.img.zst>] <device>

Write the foreign-agent recovery USB stick. EVERYTHING ON <device> IS ERASED.

Arguments:
  <device>               Whole-disk block device of the stick, e.g. /dev/sdb

Options:
  --image <path>         Use a prebuilt image (.img.zst) instead of building
                         .#images.foreign-agent-recovery (needs an aarch64 builder)
  -h, --help             Show this help

Environment:
  FA_SECRETS_DIR         Where ssh_host_ed25519_key{,.pub} live
                         (default: /mnt/pegasus/secrets/foreign-agent)
EOF
    exit "${1:-0}"
}

DEVICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) [[ -z "$DEVICE" ]] || usage 1; DEVICE="$1"; shift ;;
    esac
done
[[ -n "$DEVICE" ]] || usage 1

for f in ssh_host_ed25519_key ssh_host_ed25519_key.pub; do
    [[ -s "$SECRETS_DIR/$f" ]] || { echo "Missing $SECRETS_DIR/$f" >&2; exit 1; }
done

if [[ -z "$IMAGE" ]]; then
    cd "$(dirname "$0")/.."
    echo "Building .#images.foreign-agent-recovery ..."
    out=$(nix build .#images.foreign-agent-recovery --no-link --print-out-paths)
    IMAGE=$(echo "$out"/sd-image/*.img.zst)
fi
[[ -f "$IMAGE" ]] || { echo "Image not found: $IMAGE" >&2; exit 1; }

[[ -b "$DEVICE" ]] || { echo "$DEVICE is not a block device" >&2; exit 1; }
[[ "$(lsblk -dno TYPE "$DEVICE")" == "disk" ]] || { echo "$DEVICE is not a whole disk" >&2; exit 1; }
if lsblk -no MOUNTPOINTS "$DEVICE" | grep -q .; then
    echo "$DEVICE has mounted partitions, unmount them first:" >&2
    lsblk -o NAME,SIZE,MOUNTPOINTS "$DEVICE" >&2
    exit 1
fi

lsblk -o NAME,SIZE,MODEL,TRAN,LABEL "$DEVICE"
echo
echo "Image: $IMAGE"
read -r -p "ERASE $DEVICE and write the recovery stick? Type YES: " answer
[[ "$answer" == "YES" ]] || { echo "Aborted"; exit 1; }

echo "Writing image ..."
zstdcat "$IMAGE" | sudo dd of="$DEVICE" bs=4M iflag=fullblock conv=fsync status=progress
sudo blockdev --rereadpt "$DEVICE"
sudo udevadm settle

root_part=$(lsblk -lnpo NAME,LABEL "$DEVICE" | awk '$2 == "FA_RECOVERY" { print $1 }')
[[ -n "$root_part" ]] || { echo "No FA_RECOVERY partition on $DEVICE after writing" >&2; exit 1; }

mnt=$(mktemp -d)
trap 'sudo umount "$mnt" 2>/dev/null || true; rmdir "$mnt"' EXIT
sudo mount "$root_part" "$mnt"
sudo install -d -m 700 "$mnt/recovery"
sudo install -m 600 "$SECRETS_DIR/ssh_host_ed25519_key" "$mnt/recovery/"
sudo install -m 644 "$SECRETS_DIR/ssh_host_ed25519_key.pub" "$mnt/recovery/"
sync

echo "Recovery stick ready on $DEVICE."
