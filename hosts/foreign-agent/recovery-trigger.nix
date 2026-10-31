{ pkgs, ... }:

# Hot-plug half of the break-glass reset. The EEPROM boots USB before SD
# (BOOT_ORDER=0xf14, set once by hand), so a cold boot with the recovery stick
# in goes straight to ./recovery-stick. This covers the stick being
# plugged into a running box: reboot, and the EEPROM takes it from there.

{
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="FA_RECOVERY", TAG+="systemd", ENV{SYSTEMD_WANTS}+="recovery-reboot.service"
  '';

  systemd.services.recovery-reboot = {
    description = "Reboot into the recovery stick";
    serviceConfig.Type = "oneshot";
    script = ''
      # Coldplug replays "add" for a stick that was already in at boot. Getting
      # here then means the EEPROM fell through to SD (stick unbootable, or
      # boot order not set) - rebooting would just loop.
      uptime=$(cut -d. -f1 /proc/uptime)
      if [ "$uptime" -lt 300 ]; then
        echo "Recovery stick present at boot (uptime ''${uptime}s), not rebooting"
        exit 0
      fi
      echo "Recovery stick inserted, rebooting into it"
      systemctl reboot
    '';
  };
}
