{ config, pkgs, lib, nix-vscode-extensions, ... }:

{
  imports = [ ./home.nix ];

  programs.ssh.matchBlocks."github" = {
    host = "github.com";
    identityFile = "~/.ssh/mingaleg-1password";
  };

  # Create rclone mount directories
  home.activation.createCfoodsMnt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p $HOME/cfoods/mnt/oleg
    mkdir -p $HOME/cfoods/mnt/shared
  '';

  # Permanently mount oleg@consensusfoods.com Google Drive via rclone
  # Requires rclone remote named "cfoods-oleg" configured via `rclone config`
  systemd.user.services.rclone-cfoods-oleg = {
    Unit = {
      Description = "rclone mount: cfoods oleg Google Drive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "notify";
      ExecStart = "${pkgs.rclone}/bin/rclone mount cfoods-oleg: %h/cfoods/mnt/oleg --vfs-cache-mode writes --vfs-cache-max-size 1G";
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u %h/cfoods/mnt/oleg";
      Restart = "on-failure";
      RestartSec = "10s";
      Environment = "PATH=/run/wrappers/bin:${pkgs.fuse3}/bin:$PATH";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  systemd.user.services.rclone-cfoods-shared = {
    Unit = {
      Description = "rclone mount: cfoods shared Google Drive";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "notify";
      ExecStart = "${pkgs.rclone}/bin/rclone mount cfoods-shared: %h/cfoods/mnt/shared --vfs-cache-mode writes --vfs-cache-max-size 1G";
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u %h/cfoods/mnt/shared";
      Restart = "on-failure";
      RestartSec = "10s";
      Environment = "PATH=/run/wrappers/bin:${pkgs.fuse3}/bin:$PATH";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # mingamini-specific: Override Chrome with custom scaling for smaller UI
  home.packages = with pkgs; [
    sox
    rclone
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
