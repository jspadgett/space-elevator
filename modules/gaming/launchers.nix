# modules/gaming/launchers.nix
# The rest of your library: Epic, GOG, Amazon, itch, and everything
# that came in a Windows installer.
#
# Steam is not the whole story, so a gaming distro that ships only
# Steam has a hole in it. These are the native builds; the Flathub
# versions are also one click away in your app store if you prefer
# them sandboxed.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gaming.launchers;
in
{
  options.spaceElevator.gaming.launchers = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.gaming.enable;
      defaultText = lib.literalExpression "config.spaceElevator.gaming.enable";
      description = "Game launchers for stores other than Steam.";
    };

    heroic = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Heroic: Epic Games, GOG and Amazon Games, with Proton built in.";
    };

    lutris = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Lutris: per-game Wine prefixes and community install scripts —
        the way most non-store Windows games end up running.
      '';
    };

    protonupQt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        ProtonUp-Qt: installs and updates Proton-GE for Lutris and
        Heroic. Steam gets its copy from the steam module; these two
        manage their own.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      lib.optionals cfg.heroic [ pkgs.heroic ]
      ++ lib.optionals cfg.lutris [ pkgs.lutris ]
      ++ lib.optionals cfg.protonupQt [ pkgs.protonup-qt ];
  };
}
