# Generates a polkit rule allowing wheel users to start/stop/restart specific systemd services
# Usage:
#   imports = [ ../../modules/polkit-service-control.nix ];
#   polkitServiceControl.services = [ "wg-quick-wg-home.service" ];
{ lib, config, ... }:

{
  options.polkitServiceControl.services = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Systemd services that wheel users may start, stop, and restart without root.";
  };

  config = lib.mkIf (config.polkitServiceControl.services != []) {
    security.polkit.extraConfig =
      let
        unitList = lib.concatMapStringsSep " || "
          (svc: ''action.lookup("unit") == "${svc}"'')
          config.polkitServiceControl.services;
      in ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              (${unitList}) &&
              (action.lookup("verb") == "start" ||
               action.lookup("verb") == "stop" ||
               action.lookup("verb") == "restart") &&
              subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
      '';
  };
}
