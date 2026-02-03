{ config, pkgs, lib, nix-vscode-extensions, ... }:

{
  imports = [ ./home.nix ];

  programs.ssh.matchBlocks."github" = {
    host = "github.com";
    identityFile = "~/.ssh/mingaleg-1password";
  };

  # mingamini-specific: Override Chrome with custom scaling for smaller UI
  home.packages = with pkgs; [
    (symlinkJoin {
      name = "google-chrome";
      paths = [ google-chrome ];
      buildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/google-chrome-stable \
          --add-flags "--force-device-scale-factor=1.5" \
          --add-flags "--enable-features=VaapiVideoDecodeLinuxGL" \
          --add-flags "--disable-features=UseChromeOSDirectVideoDecoder" \
          --add-flags "--enable-gpu-rasterization" \
          --add-flags "--enable-zero-copy"

        # Patch desktop files to use the wrapped binary
        for desktop in $out/share/applications/*.desktop; do
          ${gnused}/bin/sed -i "s|${google-chrome}/bin/google-chrome-stable|$out/bin/google-chrome-stable|g" "$desktop"
        done
      '';
    })
  ];
}
