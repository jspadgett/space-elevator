# modules/gaming/gamemode.nix
# Feral GameMode + MangoHud overlay
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gaming.gamemode;
  user = config.spaceElevator.user.name;
in
{
  options.spaceElevator.gaming.gamemode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.gaming.enable;
      defaultText = lib.literalExpression "config.spaceElevator.gaming.enable";
      description = "Feral GameMode: reprioritises the machine while a game is running.";
    };

    mangohud = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install MangoHud, the in-game performance overlay.";
    };

    goverlay = lib.mkOption {
      type = lib.types.bool;
      default = cfg.mangohud;
      defaultText = lib.literalExpression "config.spaceElevator.gaming.gamemode.mangohud";
      description = ''
        GOverlay, a GUI for MangoHud — which otherwise means editing
        a config file to decide what the overlay shows.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.gamemode = {
      enable = true;
      settings.general = {
        renice = 10;
        inhibit_screensaver = 1;
      };
    };

    # renice only works for members of the gamemode group
    users.users = lib.mkIf (user != null) {
      ${user}.extraGroups = [ "gamemode" ];
    };

    warnings = lib.optional (user == null) ''
      spaceElevator.gaming.gamemode is enabled but spaceElevator.user.name is
      unset, so no account was added to the "gamemode" group — GameMode
      will not be able to renice games. Set spaceElevator.user.name, or add
      the group by hand.
    '';

    environment.systemPackages =
      lib.optionals cfg.mangohud [ pkgs.mangohud ]
      ++ lib.optionals cfg.goverlay [ pkgs.goverlay ];
  };
}
