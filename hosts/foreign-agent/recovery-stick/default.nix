{ config, pkgs, lib, self, ... }:

# Break-glass recovery stick for foreign-agent. This is its own
# nixosConfiguration (foreign-agent-recovery), NOT a module of foreign-agent:
# never import it there.
#
# Booting it (the EEPROM prefers USB over SD) unconditionally reflashes the SD
# card with the foreign-agent image built into this closure, drops
# foreign-agent's SSH host key (also its agenix identity) onto the fresh root,
# and powers off. Igor and Tanya then pull the stick and power the box back on.
# See foreign-agent.md.
#
# The host key is not in the nix store: scripts/make-foreign-agent-recovery.sh
# copies it to /recovery on the stick after writing the image.

let
  target = "/dev/mmcblk0";
  fa = self.nixosConfigurations.foreign-agent.config;
  # The compressed image, stored so that it does not drag foreign-agent's
  # whole system closure (~2.5GiB, uncompressed) onto the stick. Copying the
  # file alone is not enough: zstd keeps each store path's first occurrence as
  # a literal, so nix's reference scanner still finds every hash. Swapping
  # letter case hides them (store hashes are lowercase) and is its own inverse,
  # so the reflash just swaps back while streaming.
  swapCase = "tr a-zA-Z A-Za-z";
  payload = pkgs.runCommand "foreign-agent-sd-image.img.zst.swapcase" {
    allowedReferences = [ ];
  } ''
    ${swapCase} < ${fa.system.build.sdImage}/${fa.image.filePath} > $out
  '';
  keyDir = "/recovery";
in
{
  imports = [
    ../../../modules/core-common
    ../../../modules/rpi-slim.nix
  ];

  networking.hostName = "foreign-agent-recovery";

  # Must differ from the SD image's labels and IDs: both disks are attached
  # while this runs, and "/" is found by label.
  sdImage = {
    rootVolumeLabel = "FA_RECOVERY";
    firmwarePartitionName = "FA_RECFW";
    firmwarePartitionID = lib.mkForce "0x5ec0e7a1";
    rootPartitionUUID = "fa0fa0fa-4a00-4c0e-8e0f-0000000000fa";
    expandOnBoot = false;
    # nixos-raspberrypi sizes this for many kernel generations; the stick only
    # ever has one.
    firmwareSize = lib.mkForce 256;
  };

  boot.initrd.availableKernelModules = [ "usb_storage" "uas" ];

  # For debugging a failed reflash: console login, or SSH over ethernet DHCP.
  users.users.mingaleg.hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
  };
  security.sudo.wheelNeedsPassword = false;

  systemd.services.foreign-agent-reflash = {
    description = "Reflash foreign-agent's SD card and power off";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = with pkgs; [ coreutils util-linux zstd systemd ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
    script = ''
      set -euo pipefail

      # Green ACT LED: steady blink while working, heartbeat on failure.
      led() {
        for l in /sys/class/leds/ACT /sys/class/leds/led0; do
          if [ -w "$l/trigger" ]; then echo "$1" > "$l/trigger"; return; fi
        done
      }
      trap 'led heartbeat; echo "foreign-agent-reflash FAILED" >&2' ERR

      [ -b ${target} ] || { echo "No SD card at ${target}" >&2; false; }
      case "$(findmnt -no SOURCE /)" in
        ${target}*) echo "Refusing to flash the disk we booted from" >&2; false ;;
      esac
      for f in ssh_host_ed25519_key ssh_host_ed25519_key.pub; do
        [ -s ${keyDir}/$f ] || { echo "Missing ${keyDir}/$f on the stick" >&2; false; }
      done

      led timer
      echo "Writing ${payload} to ${target}"
      umount ${target}p* 2>/dev/null || true
      ${swapCase} < ${payload} | zstdcat | dd of=${target} bs=4M iflag=fullblock conv=fsync status=none
      blockdev --rereadpt ${target}
      udevadm settle

      mnt=$(mktemp -d)
      mount ${target}p2 "$mnt"
      install -d -m 755 "$mnt/etc/ssh"
      install -m 600 ${keyDir}/ssh_host_ed25519_key "$mnt/etc/ssh/"
      install -m 644 ${keyDir}/ssh_host_ed25519_key.pub "$mnt/etc/ssh/"
      sync
      umount "$mnt"

      echo "Reflash done, powering off"
      led default-on
      sleep 5
      systemctl poweroff
    '';
  };

  system.stateVersion = "25.11";
}
