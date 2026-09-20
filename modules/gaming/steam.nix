# modules/gaming/steam.nix
# Steam with Remote Play, local game transfers, gamescope, GE-Proton
# and protontricks. Controllers live in controllers.nix.
#
# Worth knowing: the nixpkgs Steam module already gives us steam-run
# (an FHS shell for running downloaded binaries), the steam-hardware
# udev rules, 32-bit graphics and 32-bit PipeWire. None of that needs
# repeating here.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gaming.steam;
in
{
  options.spaceElevator.gaming.steam = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.gaming.enable;
      defaultText = lib.literalExpression "config.spaceElevator.gaming.enable";
      description = "Steam, with gamescope and GE-Proton alongside it.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the ports Remote Play, dedicated servers and local network
        game transfers need.
      '';
    };

    protonGE = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Preinstall GE-Proton: pick it per-game under Properties ->
        Compatibility for titles the stock Proton struggles with.
      '';
    };

    protontricks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        protontricks: installs the Windows runtime bits (fonts, DLLs,
        .NET) that individual games turn out to need. The first thing
        to reach for when a game won't start.
      '';
    };

    gamescopeSession = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Add a "Steam Big Picture" session to the login screen: the
        machine boots straight into a SteamOS-style console interface
        instead of a desktop. Meant for a TV or a handheld; on a
        normal desktop you probably want the desktop.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = cfg.openFirewall;
      dedicatedServer.openFirewall = cfg.openFirewall;
      localNetworkGameTransfers.openFirewall = cfg.openFirewall;
      extraCompatPackages = lib.optionals cfg.protonGE [ pkgs.proton-ge-bin ];

      protontricks.enable = cfg.protontricks;
      gamescopeSession.enable = cfg.gamescopeSession;
    };

    programs.gamescope = {
      enable = true;
      # capSysNice grants gamescope realtime scheduling, but on NixOS it
      # is known to prevent games launching from *within* Steam
      # (pressure-vessel can't inherit the capability). Keep it off.
      capSysNice = false;
    };
  };
}
