{ config, lib, pkgs, mingadocs, ... }:

# mingadocs (github:mingaleg/mingadocs): scans paper documents on the office
# printer's scanner, files them as PDFs, and prints their ARN labels. Served as
# http://docs.ronove by web-proxy.nix; the app itself has no login, so nginx
# only lets the LAN and VPN in.

let
  layout = import ../../home-network/layout.nix;
  printer = layout.machines.officeprinter.interfaces.wlan.ip;
  scannerUrl = "https://officeprinter.${layout.domain}:443";

  # SANE's config with the scanner declared in escl.conf, so `scanimage -L`
  # (mingadocs' device list) shows it without mDNS discovery - there's no
  # Avahi on ronove. No model name after the URL: with a host name instead of
  # an IP, sane-backends 1.4.0 then fails to list the device at all.
  saneConfig = pkgs.runCommand "mingadocs-sane-config" { } ''
    cp -r ${pkgs.sane-backends}/etc/sane.d $out
    chmod -R u+w $out
    echo "device ${scannerUrl}" >> $out/escl.conf
  '';
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

  # Label printing. Local-only CUPS with one driverless queue; the name is what
  # mingadocs' print settings refer to. The printer takes PWG raster (it's
  # AirPrint), so cups-filters' generic PPD drives it. Not model "everywhere":
  # that builds the PPD by querying the printer, so every deploy while it's
  # off or asleep would fail ensure-printers.
  services.printing.enable = true;
  hardware.printers.ensurePrinters = [
    {
      name = "OfficePrinter";
      description = "HP LaserJet MFP M232";
      deviceUri = "ipp://${printer}/ipp/print";
      model = "drv:///cupsfilters.drv/pwgrast.ppd";
      ppdOptions.PageSize = "A4";
    }
  ];

  # Scanning goes through SANE's built-in eSCL backend; the device mingadocs
  # has stored is escl:${scannerUrl}.
  hardware.sane.enable = true;
  systemd.services.mingadocs.environment.SANE_CONFIG_DIR = "${saneConfig}";
}
