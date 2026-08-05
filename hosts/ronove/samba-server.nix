{ config, pkgs, ... }:

{
  # Samba server configuration
  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "Ronove Storage";
        "netbios name" = "ronove";
        security = "user";
        "hosts allow" = "192.168.0.0/16 172.26.0.0/16 10.100.0.0/24 10.200.0.0/24";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";

        "strict locking" = "no";
        "kernel oplocks" = "no";
        "server min protocol" = "SMB3";
        "server signing" = "disabled";
      };

      pegasus = {
        path = "/mnt/pegasus";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "mingaleg";
        "force user" = "mingaleg";
        "create mask" = "0664";
        "directory mask" = "0775";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
