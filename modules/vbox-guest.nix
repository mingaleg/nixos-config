{ config, pkgs, lib, ... }:

{
  # TODO: remove me after https://github.com/NixOS/nixpkgs/pull/86473 is applied
  # services.xserver.videoDrivers = lib.mkForce [ "vmware" "virtualbox" "modesetting" ];
  # systemd.services.virtualbox-resize = {
  #  description = "VirtualBox Guest Screen Resizing";

  #  wantedBy = [ "multi-user.target" ];
  #  requires = [ "dev-vboxguest.device" ];
  #  after = [ "dev-vboxguest.device" ];

  #  unitConfig.ConditionVirtualization = "oracle";

  #  serviceConfig.ExecStart = "${config.boot.kernelPackages.virtualboxGuestAdditions}/bin/VBoxClient -fv --vmsvga";
  #};

  virtualisation.virtualbox.guest = {
    enable = true;
    x11 = true;
  };
}
