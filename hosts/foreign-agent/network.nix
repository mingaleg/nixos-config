{ config, ... }:

# Ethernet whenever a cable is plugged in, otherwise Wi-Fi: Igor and Tanya's
# Solnd082 first, then mingahome (so the box also comes up at home before it
# ships). Wi-Fi may stay associated while ethernet is up, but ethernet's lower
# route metric means all traffic leaves through the cable.

let
  wifi = { ssid, pskVar, priority, metric }: {
    connection = {
      id = ssid;
      type = "wifi";
      autoconnect = true;
      autoconnect-priority = priority;
    };
    wifi = {
      inherit ssid;
      mode = "infrastructure";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "$" + pskVar;
    };
    ipv4 = { method = "auto"; route-metric = metric; };
    ipv6 = { method = "auto"; route-metric = metric; };
  };
in
{
  # SOLND082_PSK / MINGAHOME_PSK, substituted into the profiles below.
  age.secrets.foreign-agent-wifi.file = ../../secrets/foreign-agent-wifi.age;

  networking.networkmanager = {
    enable = true;
    # Brought up by networking.wireguard, not NetworkManager.
    unmanaged = [ "wg-home" ];

    ensureProfiles = {
      environmentFiles = [ config.age.secrets.foreign-agent-wifi.path ];
      profiles = {
        ethernet = {
          connection = {
            id = "ethernet";
            type = "ethernet";
            interface-name = "end0";
            autoconnect = true;
            autoconnect-priority = 100;
          };
          ipv4 = { method = "auto"; route-metric = 100; };
          ipv6 = { method = "auto"; route-metric = 100; };
        };
        Solnd082 = wifi { ssid = "Solnd082"; pskVar = "SOLND082_PSK"; priority = 20; metric = 600; };
        mingahome = wifi { ssid = "mingahome"; pskVar = "MINGAHOME_PSK"; priority = 10; metric = 700; };
      };
    };
  };
}
