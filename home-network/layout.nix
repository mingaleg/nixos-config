let
  domain = "home.mingalev.net";
  networkPrefix = "172.26.249";
  vpnNetworkPrefix = "10.100.0";

  ip = suffix: "${networkPrefix}.${toString suffix}";
  vpnIp = suffix: "${vpnNetworkPrefix}.${toString suffix}";

  network = {
    prefix = networkPrefix;
    prefixLength = 24;
    netmask = "255.255.255.0";
    defaultGateway = ip 254;
    dhcp = {
      start = ip 180;
      end = ip 249;
      leaseTime = "7h";
    };
  };

  machines = {
    mingapred = {
      interfaces = {
        wlan = {
          ip = ip 1;
          mac = "28:d0:ea:c9:d0:a1";
        };
        eth = { # usb dongle
          ip = ip 2;
          mac = "6c:1f:f7:19:86:5d";
        };
      };
    };

    mingamac = {
      interfaces.wlan = {
        ip = ip 10;
        mac = "f4:5c:89:8a:82:8f";
      };
    };
    mingamini = {
      interfaces.wlan = {
        ip = ip 11;
        mac = "f4:7b:09:f7:f0:1c";
      };
      interfaces.eth = {
        ip = ip 12;
        mac = "06:e0:4c:6a:00:04";
      };
      vpn = {
        ip = vpnIp 80;
        publicKey = "TpXIsf+dtUrSj9zI9+yYs35C/k4lTmzJwbYaIIw9WBY=";
      };
    };

    pixel10 = {
      interfaces.wlan = {
        ip = ip 50;
        mac = "b0:d5:fb:b7:b9:22";
      };
      vpn = {
        ip = vpnIp 10;
        publicKey = "WzQNq6q9JlWsTz7L1ejHHII1SFoHYhQAy/XNahwKClU=";
      };
    };

    chromecast-ultra = {
      interfaces.wlan = {
        ip = ip 159;
        mac = "00:f6:20:79:3d:4f";
      };
    };

    keenetic = {
      interfaces.eth = {
        ip = ip 252;
        mac = "e4:18:6b:28:a0:70";
      };
    };
    pi = {
      interfaces.eth = {
        ip = ip 251;
        mac = "2c:cf:67:cc:55:39";
      };
    };
    ronove = {
      interfaces.eth = {
        ip = ip 253;
        mac = "64:00:6a:38:f1:37";
      };
    };
    linksys = {
      interfaces.eth = {
        ip = ip 254;
        mac = "80:69:1a:d7:62:fc";
      };
    };

    # This one is special -- it lives in its own network shared with pi
    # Does not need DHCP, but we still define the host for DNS.
    modem = {
      interfaces.usb = {
        ip = "192.168.8.1";
      };
    };

    # Roamers
    igor = {
      vpn = {
        ip = vpnIp 11;
        publicKey = "oOkMYPF/12FDQOPcCLWYrW+vCXkivl5LNzqax1U2YE8=";
      };
    };
    tanya = {
      vpn = {
        ip = vpnIp 12;
        publicKey = "QV2Bdze5tUj5Q0JFU4FZeG6RE1G5EaGbx3jFaJCvElg=";
      };
    };
  };

in {
  inherit domain network machines;
}
