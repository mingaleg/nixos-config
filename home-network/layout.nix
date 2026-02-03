let
  domain = "home.mingalev.net";
  networkPrefix = "172.26.249";

  ip = suffix: "${networkPrefix}.${toString suffix}";

  network = {
    prefix = networkPrefix;
    prefixLength = 24;
    netmask = "255.255.255.0";
    router = ip 254;
    dhcp = {
      start = ip 100;
      end = ip 149;
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

    chromecast-ultra = {
      ip = ip 159;
      mac = "00:f6:20:79:3d:4f";
    };

    pi = {
      ip = ip 253;
      mac = "2c:cf:67:cc:55:39";
    };
    linksys = {
      ip = ip 254;
      # No MAC - router, not a DHCP client
    };
  };

in {
  inherit domain network machines;
}
