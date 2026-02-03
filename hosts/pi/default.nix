{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = lib.optionals (builtins.pathExists ./hardware-configuration.nix) [
    ./hardware-configuration.nix
  ] ++ [
    ./samba-server.nix
    ./pihole.nix
  ];

  networking.hostName = "pi";
  
  nix.settings.trusted-users = [ "root" "mingaleg" ];
  
  fileSystems."/mnt/pegasus" = {
    device = "/dev/disk/by-uuid/B66C1D7C6C1D3897";
    fsType = "ntfs-3g";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "dmask=022" "fmask=133" ];
  };
  
  # Static IP for the DHCP/DNS server
  networking.useDHCP = false;
  networking.interfaces.end0 = {
    ipv4.addresses = [{
      address = layout.machines.pi.ip;
      prefixLength = layout.network.prefixLength;
    }];
  };
  networking.defaultGateway = layout.network.defaultGateway;
  networking.nameservers = [ "127.0.0.1" "1.1.1.1" ];  # Use itself for DNS
  
  services.openssh.enable = true;
  
  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
    hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";
  };

  environment.systemPackages = with pkgs; [
    vim git htop tmux ntfs3g
    ethtool iproute2 pciutils usbutils
    iperf3 curl wget bind speedtest-cli
  ];

  boot.kernel.sysctl = {
    "net.core.rmem_max" = 134217728;      # 128 MB
    "net.core.wmem_max" = 134217728;      # 128 MB
    "net.core.rmem_default" = 16777216;   # 16 MB default
    "net.core.wmem_default" = 16777216;   # 16 MB default
    
    # TCP auto-tuning buffers: min 4KB, default 16MB, max 128MB
    "net.ipv4.tcp_rmem" = "4096 16777216 134217728";
    "net.ipv4.tcp_wmem" = "4096 16777216 134217728";
    
    # TCP memory in pages (4KB each): min 16MB, pressure 64MB, max 256MB
    "net.ipv4.tcp_mem" = "4096 16384 65536";
    
    # Prevents performance drop after connection pause
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    
    # Optimise for high network throughput
    "net.ipv4.tcp_window_scaling" = 1;
    "net.ipv4.tcp_timestamps" = 1;
    "net.ipv4.tcp_sack" = 1;
    "net.ipv4.tcp_fack" = 1;
    
    # Increase max backlog queue
    "net.core.netdev_max_backlog" = 16384;
    
    # Optimize TCP parameters
    "net.ipv4.tcp_congestion_control" = "cubic";  # BBR not available in kernel
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_mtu_probing" = 1;
    
    # Increase local port range
    "net.ipv4.ip_local_port_range" = "10000 65535";
  };

  # Maximize ring buffers
  systemd.services.network-optimization = {
    description = "Optimize Network Performance";
    after = [ "network-pre.target" ];
    before = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "optimize-network" ''
        set -e
        
        IFACE="end0"
        
        echo "Waiting for $IFACE..."
        for i in {1..30}; do
          if [ -e /sys/class/net/$IFACE ]; then
            break
          fi
          sleep 1
        done
        
        if [ ! -e /sys/class/net/$IFACE ]; then
          echo "$IFACE not found"
          exit 0
        fi
        
        echo "Waiting for link up..."
        for i in {1..30}; do
          if [ "$(cat /sys/class/net/$IFACE/operstate)" = "up" ]; then
            break
          fi
          sleep 1
        done
        
        echo "=== Network Optimization Starting ==="
        
        # Maximize ring buffers
        echo "Setting ring buffers to maximum..."
        ${pkgs.ethtool}/bin/ethtool -G $IFACE rx 8192 tx 4096 || echo "Note: ring buffer adjustment had warnings"
        
        # Increase txqueuelen
        echo "Increasing txqueuelen..."
        ${pkgs.iproute2}/bin/ip link set $IFACE txqueuelen 10000 || true
        
        # Verify offload features
        echo "Verifying hardware offload..."
        ${pkgs.ethtool}/bin/ethtool -K $IFACE gso on gro on tso on || true
        
        # Optimize interrupt coalescing
        echo "Optimizing interrupt coalescing..."
        ${pkgs.ethtool}/bin/ethtool -C $IFACE rx-usecs 100 tx-usecs 100 || echo "Note: coalescing adjustment had warnings"
        
        echo "=== Optimization Complete ==="
        echo ""
        echo "Final settings:"
        ${pkgs.ethtool}/bin/ethtool $IFACE | grep -E "Speed|Duplex" || true
        echo ""
        echo "Ring buffers configured (check with: ethtool -g end0)"
        echo "txqueuelen set to 10000"
        
        # Always exit 0 even if some commands warned
        exit 0
      '';
    };
  };

  # Force CPU to performance governor
  powerManagement.cpuFreqGovernor = "performance";  
  # Alternatively, use ondemand but with better settings
  # powerManagement.cpuFreqGovernor = "ondemand";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
