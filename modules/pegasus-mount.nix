{ config, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.cifs-utils ];

  age.secrets.smb-credentials-pegasus = {
    file = ../secrets/smb-credentials-pegasus.age;
    owner = "root";
    mode = "0400";
  };

  fileSystems."/mnt/pegasus" = {
    device = "//ronove/pegasus";
    fsType = "cifs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "credentials=${config.age.secrets.smb-credentials-pegasus.path}"
      "uid=1001"
      "gid=100"
      "file_mode=0664"
      "dir_mode=0775"
      "cache=loose"
    ];
  };
}
