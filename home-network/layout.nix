let
  domain = "home.mingalev.net";
  networkPrefix = "172.26.249";

  ip = suffix: "${networkPrefix}.${toString suffix}";

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
      ip = ip 1;
      mac = "28:d0:ea:c9:d0:a1";
    };

    mingamac = {
      ip = ip 10;
      mac = "f4:5c:89:8a:82:8f";
    };
    mingamini = {
      ip = ip 11;
      mac = "f4:7b:09:f7:f0:1c";
    };

    pixel10 = {
      ip = ip 50;
      mac = "b0:d5:fb:b7:b9:22";
    };

    chromecast-ultra = {
      ip = ip 159;
      mac = "00:f6:20:79:3d:4f";
    };

    keenetic = {
      ip = ip 252;
      mac = "e4:18:6b:28:a0:70";
    }
    pi = {
      ip = ip 253;
      mac = "2c:cf:67:cc:55:39";
    };
    linksys = {
      ip = ip 254;
      mac = "80:69:1a:d7:62:fc";
    };
  };

in {
  inherit domain network machines;
}
