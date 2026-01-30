{ config, pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    ./default.nix
  ];

  # SD image specific settings
  sdImage.compressImage = true;
}
