{ config, lib, mingadocs, ... }:

# mingadocs (github:mingaleg/mingadocs): scans paper documents on the office
# printer's scanner, files them as PDFs, and prints their ARN labels. Served as
# http://docs.ronove by web-proxy.nix; the app itself has no login, so nginx
# only lets the LAN and VPN in.

let
  layout = import ../../home-network/layout.nix;
  printer = layout.machines.officeprinter.interfaces.wlan.ip;
in
{
  imports = [ mingadocs.nixosModules.default ];

  age.secrets.mingadocs-secret-key.file = ../../secrets/mingadocs-secret-key.age;

  services.mingadocs = {
    enable = true;
    # Scans and PDFs on the big disk; the SQLite DB stays on the system SSD.
    mediaDir = "/mnt/pegasus/mingadocs";
    allowedHosts = [ "docs.ronove" "docs.ronove.${layout.domain}" ];
    secretKeyFile = config.age.secrets.mingadocs-secret-key.path;
  };

  # nginx serves the documents straight from disk; mingaleg reads them over
  # the pegasus Samba share. Both only through the group's read bits.
  users.users.nginx.extraGroups = [ "mingadocs" ];
  users.users.mingaleg.extraGroups = [ "mingadocs" ];

  # Label printing. Local-only CUPS with one driverless (IPP Everywhere /
  # AirPrint) queue; the name is what mingadocs' print settings refer to.
  services.printing.enable = true;
  hardware.printers.ensurePrinters = [
    {
      name = "OfficePrinter";
      description = "HP LaserJet MFP M232";
      deviceUri = "ipp://${printer}/ipp/print";
      model = "everywhere";
      ppdOptions.PageSize = "A4";
    }
  ];

  # Scanning goes through SANE's built-in eSCL backend straight to the
  # printer's address, so no discovery or extra backends are needed.
  hardware.sane.enable = true;
}
