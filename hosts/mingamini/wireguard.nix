{ config, pkgs, lib, ... }:

{
  age.identityPaths = [ "/root/.ssh/agenix-hosts" ];

  age.secrets.wireguard-mingamini = {
    file = ../../secrets/wireguard-mingamini.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wg-quick.interfaces = {
    wg-home = {
      address = [ "10.100.0.80/24" ];
      privateKeyFile = config.age.secrets.wireguard-mingamini.path;
      dns = [ "172.26.249.253" ];

      peers = [
        {
          # VPS
          publicKey = "TnZpPk/diUblm/aQG/dm9yqFPCnfjQrZ/g5xwoAcChU=";
          allowedIPs = [ "172.26.249.0/24" ];
          endpoint = "home-gw.mingalev.net:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };

  systemd.services."wg-quick-wg-home".wantedBy = lib.mkForce [];
}
