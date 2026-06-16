{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = [ ../../modules/polkit-service-control.nix ];

  polkitServiceControl.services = [ "wg-quick-wg-home.service" ];
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
      mtu = 1380;

      peers = [
        {
          # VPS
          publicKey = "TnZpPk/diUblm/aQG/dm9yqFPCnfjQrZ/g5xwoAcChU=";
          # allowedIPs = [ "10.100.0.0/24" "172.26.249.0/24" ];
          allowedIPs = [ "0.0.0.0/0" ];
          endpoint = "home-gw.mingalev.net:51820";
          persistentKeepalive = 25;
        }
      ];
    };
  };

  systemd.services."wg-quick-wg-home".wantedBy = lib.mkForce [];

  # Auto start/stop wg-home based on wifi network:
  # - on mingahome wifi: stop (already home)
  # - on any other network with internet: start
  systemd.services.wg-home-autoconnect = {
    description = "Auto start/stop wg-home based on network location";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "wg-home-autoconnect" ''
        MINGAHOME_SSID="mingahome"
        HOME_GATEWAY="${layout.network.defaultGateway}"

        is_at_home() {
          # Check wifi SSID
          for iface in $(${pkgs.iw}/bin/iw dev 2>/dev/null | ${pkgs.gawk}/bin/awk '/Interface/{print $2}'); do
            ssid=$(${pkgs.iw}/bin/iw dev "$iface" link 2>/dev/null | ${pkgs.gawk}/bin/awk -F': ' '/SSID/{print $2}')
            if [[ "$ssid" == "$MINGAHOME_SSID" ]]; then
              return 0
            fi
          done
          # Check if home gateway is reachable via any non-wg interface (bypasses tunnel)
          for iface in $(${pkgs.iproute2}/bin/ip link show | ${pkgs.gawk}/bin/awk -F': ' '/^[0-9]+:/{print $2}' | grep -v -E '^(wg|lo)'); do
            ${pkgs.iputils}/bin/ping -c1 -W2 -I "$iface" "$HOME_GATEWAY" >/dev/null 2>&1 && return 0
          done
          return 1
        }

        has_internet() {
          ${pkgs.iputils}/bin/ping -c1 -W3 1.1.1.1 >/dev/null 2>&1
        }

        if is_at_home; then
          systemctl stop wg-quick-wg-home.service 2>/dev/null || true
        elif has_internet; then
          systemctl start wg-quick-wg-home.service 2>/dev/null || true
        fi
      '';
    };
  };

  # Watch for IP address changes (wifi/ethernet connect/disconnect) and trigger the check
  systemd.services.wg-home-network-monitor = {
    description = "Trigger wg-home autoconnect on network changes";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      ExecStart = pkgs.writeShellScript "wg-home-network-monitor" ''
        ${pkgs.iproute2}/bin/ip monitor address | while read -r _line; do
          systemctl start wg-home-autoconnect.service 2>/dev/null || true
        done
      '';
    };
  };
}
