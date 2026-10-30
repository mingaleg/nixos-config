{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
  vpsPublicKey = "TnZpPk/diUblm/aQG/dm9yqFPCnfjQrZ/g5xwoAcChU=";
  homeNet = "${layout.network.prefix}.0/${toString layout.network.prefixLength}";
in
{
  age.secrets.wireguard-foreign-agent-private = {
    file = ../../secrets/wireguard-foreign-agent-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  # Road-warrior peer on vps's wg-clients (derived there from layout.nix), so
  # it's reachable as foreign-agent / 10.100.0.33 from other VPN clients and,
  # via ronove, from the home LAN.
  networking.wireguard.interfaces.wg-home = {
    ips = [ "${layout.machines.foreign-agent.vpn.ip}/24" ];
    privateKeyFile = config.age.secrets.wireguard-foreign-agent-private.path;
    mtu = 1380;

    # The home LAN has to be in allowedIPs, or packets from home LAN clients
    # (forwarded by ronove without NAT) are dropped. But as a plain route it
    # would shadow the on-link route whenever the box itself sits on
    # mingahome - taking the default gateway with it. So install it by hand,
    # with a metric that loses to any directly connected route.
    allowedIPsAsRoutes = false;
    peers = [
      {
        publicKey = vpsPublicKey;
        allowedIPs = [ "10.100.0.0/24" homeNet ];
        endpoint = "home-gw.mingalev.net:51820";
        persistentKeepalive = 25;
        # Boot often races Wi-Fi association; keep retrying DNS for the endpoint.
        dynamicEndpointRefreshSeconds = 60;
      }
    ];

    postSetup = ''
      ${pkgs.iproute2}/bin/ip route replace ${homeNet} dev wg-home metric 1000
    '';
    postShutdown = ''
      ${pkgs.iproute2}/bin/ip route del ${homeNet} dev wg-home metric 1000 || true
    '';
  };

  # Last line of defence against a wedged network stack: if vps hasn't
  # completed a handshake for an hour, reboot. If vps itself is down this
  # reboots hourly, which is harmless.
  systemd.services.wg-handshake-watchdog = {
    description = "Reboot if the WireGuard tunnel to vps has been dead for an hour";
    serviceConfig.Type = "oneshot";
    script = ''
      uptime=$(cut -d. -f1 /proc/uptime)
      [ "$uptime" -gt 3600 ] || exit 0

      last=$(${pkgs.wireguard-tools}/bin/wg show wg-home latest-handshakes 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -v k="${vpsPublicKey}" '$1 == k { print $2 }')
      age=$(( $(date +%s) - ''${last:-0} ))
      if [ "$age" -gt 3600 ]; then
        echo "No handshake with vps for ''${age}s, rebooting"
        systemctl reboot
      fi
    '';
  };
  systemd.timers.wg-handshake-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "15min";
    };
  };
}
