{ config, pkgs, lib, ... }:

{
  age.secrets.murmur-env = {
    file = ../../secrets/murmur-env.age;
    owner = "root";
    mode = "0400";
  };

  services.murmur = {
    enable = true;
    openFirewall = true;
    bandwidth = 72000;
    users = 10;
    registerName = "mingaleg's Mumble";
    # Substituted at runtime from environmentFile via envsubst
    password = "$MURMUR_SERVER_PASSWORD";
    environmentFile = config.age.secrets.murmur-env.path;
  };

  # Set the SuperUser (admin) password on every start, after the ini file is written
  systemd.services.murmur.preStart = lib.mkAfter ''
    ${config.services.murmur.package}/bin/mumble-server \
      -supw "$MURMUR_SUPW" \
      -ini /run/murmur/murmurd.ini
  '';
}
