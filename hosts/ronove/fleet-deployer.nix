{ config, lib, fleet-deployer, ... }:

# ronove as the fleet's build & release hub: tracks main of this repo, shows
# every host's state on a dashboard (http://ronove.home.mingalev.net:8090) and
# deploys on request (button or API). It never deploys on its own.

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = [ fleet-deployer.nixosModules.default ];

  # foreign-agent is aarch64: build it here under emulation, like mingamini
  # does. The rpi cache has some of what the nixos-raspberrypi flake needs.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  nix.settings = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  # Owned by root: the service gets them through systemd's LoadCredential.
  age.secrets.fleet-deployer-ssh.file = ../../secrets/fleet-deployer-ssh.age;
  age.secrets.fleet-deployer-token.file = ../../secrets/fleet-deployer-token.age;

  services.fleet-deployer = {
    enable = true;
    repoUrl = "https://github.com/mingaleg/nixos-config.git";
    sshUser = "mingaleg";
    sshKeyFile = config.age.secrets.fleet-deployer-ssh.path;
    tokenFile = config.age.secrets.fleet-deployer-token.path;
    # Anyone at home or on the VPN may deploy from the dashboard; the token is
    # for API use from anywhere else.
    trustedNetworks = [
      "${layout.network.prefix}.0/${toString layout.network.prefixLength}"
      "10.100.0.0/24" # WireGuard VPN clients (via vps)
      "127.0.0.0/8"
    ];
    hosts = {
      ronove.target = "localhost";
      vps.target = "home-gw.mingalev.net";
      foreign-agent.target = "foreign-agent.${layout.domain}";
      # Deployed as root: its key there only accepts ronove's addresses.
      mingamini = {
        target = "mingamini.${layout.domain}";
        user = "root";
      };
    };
  };

  # LAN; wg0 (VPN clients) is already a trusted interface.
  networking.firewall.interfaces.enp2s0.allowedTCPPorts = [ config.services.fleet-deployer.listen.port ];

  # The deployer checks host keys strictly against these.
  programs.ssh.knownHosts = {
    ronove = {
      hostNames = [ "localhost" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKbDbFGD26zzHCHB6lc6KcnMFRl+VSyEPP+zgTxmhDQs";
    };
    vps = {
      hostNames = [ "home-gw.mingalev.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLXM8PYt0Dph5//GoNckxsjojZ62IgnmWGQ9kTgGngQ";
    };
    foreign-agent = {
      hostNames = [ "foreign-agent.${layout.domain}" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHhd0gkmCKyDbeKV94CaAX/OeFYW4Aq+S/MAq92rfNNy";
    };
    mingamini = {
      hostNames = [ "mingamini.${layout.domain}" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIARNXDv35BAzNUx4276PvXYAs0wgoJL+KMQMtTJTDM1G";
    };
  };
}
