{ config, pkgs, lib, ... }:

{
  options.networkTuning.interface = lib.mkOption {
    type = lib.types.str;
    description = "LAN interface to apply throughput tuning (sysctls, ring buffers) to.";
  };

  config = {
    boot.kernel.sysctl = {
      # Enable IP forwarding for VPN
      "net.ipv4.ip_forward" = 1;

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

          IFACE="${config.networkTuning.interface}"

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
          echo "Ring buffers configured (check with: ethtool -g $IFACE)"
          echo "txqueuelen set to 10000"

          # Always exit 0 even if some commands warned
          exit 0
        '';
      };
    };
  };
}
