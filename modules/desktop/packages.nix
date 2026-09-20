# modules/desktop/packages.nix
# Everyday desktop applications plus the file/disk/system plumbing a
# mainstream distro ships by default.
#
# This set is deliberately the same on every desktop environment, so a
# machine behaves the same way whichever session you log into. Anything
# a particular desktop needs *instead* (its own file manager, its app
# store) lives in that desktop's module.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.desktop.packages;
in
{
  options.spaceElevator.desktop.packages = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.desktop.enable;
      defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
      description = ''
        The common application set: browser, terminal, media players,
        office suite, archive and filesystem tools, disk utilities and
        system diagnostics. Identical across desktop environments.
      '';
    };

    firefox = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Firefox as the default browser. Installed through
        programs.firefox, so enterprise policies and native messaging
        work. Turn it off if you would rather install another browser
        yourself — no desktop here ships one otherwise.
      '';
    };

    vesktop = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Vesktop, a Discord client. Preferred over the official one
        because screen sharing *with audio* works on Wayland, which
        every desktop here defaults to.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.firefox.enable = cfg.firefox;

    environment.systemPackages = with pkgs; [
      # Everyday apps (the browser is programs.firefox, above)
      kitty
      mpv
      imv
      libreoffice
      file-roller
      pavucontrol

      # Archive backends (file-roller and friends shell out to these)
      zip
      unzip
      p7zip
      unrar

      # Disk formatting & partitioning (udisks2/file managers need the
      # mkfs backends to format removable drives)
      gparted
      dosfstools   # FAT32
      exfatprogs   # exFAT
      ntfs3g       # NTFS
      smartmontools # disk health (smartctl)

      # File & system diagnosis
      file
      tree
      ncdu
      btop
      usbutils     # lsusb
      pciutils     # lspci
    ]
    ++ lib.optionals cfg.vesktop [ pkgs.vesktop ];
  };
}
