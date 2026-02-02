{ config, pkgs, lib, ... }:

{
  imports = lib.optionals (builtins.pathExists ./hardware-configuration.nix) [
    ./hardware-configuration.nix
  ] ++ [
    ./samba-server.nix
  ];

  networking.hostName = "pi";
  
  nix.settings.trusted-users = [ "root" "mingaleg" ];
  
  fileSystems."/mnt/pegasus" = {
    device = "/dev/disk/by-uuid/B66C1D7C6C1D3897";
    fsType = "ntfs-3g";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "dmask=022" "fmask=133" ];
  };
  
  networking.networkmanager.enable = true;
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" ];
  
  services.openssh.enable = true;
  
  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
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
        
        # Maximize ring buffers (hardware supports RX:8192, TX:4096)
        echo "Setting ring buffers to maximum..."
        ${pkgs.ethtool}/bin/ethtool -G $IFACE rx 8192 tx 4096 2>&1 || echo "Could not set ring buffers"
        
        # Increase txqueuelen for better buffering
        echo "Increasing txqueuelen..."
        ${pkgs.iproute2}/bin/ip link set $IFACE txqueuelen 10000
        
        # Verify offload features are enabled
        echo "Verifying hardware offload..."
        ${pkgs.ethtool}/bin/ethtool -K $IFACE gso on gro on tso on 2>&1 || true
        
        # Optimize interrupt coalescing (balance latency vs throughput)
        echo "Optimizing interrupt coalescing..."
        ${pkgs.ethtool}/bin/ethtool -C $IFACE rx-usecs 100 tx-usecs 100 2>&1 || echo "Could not adjust coalescing"
        
        echo "=== Optimization Complete ==="
        echo ""
        echo "Ring buffers:"
        ${pkgs.ethtool}/bin/ethtool -g $IFACE 2>&1 | grep -A 4 "Current hardware"
        echo ""
        echo "Link status:"
        ${pkgs.ethtool}/bin/ethtool $IFACE | grep -E "Speed|Duplex"
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
