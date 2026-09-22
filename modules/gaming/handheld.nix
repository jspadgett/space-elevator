# modules/gaming/handheld.nix
# Handheld gaming PCs: ROG Ally, Legion Go, GPD Win, MSI Claw, AYANEO,
# OneXPlayer — whatever Handheld Daemon (hhd) recognises. The Steam
# Deck is covered too, though Jovian-NixOS is the deeper fit there.
#
# Off by default — it runs a daemon that takes over the gamepad, TDP
# and power profiles, which is only right on hardware that has them.
# The wizard turns it on when it detects one of these machines.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.gaming.handheld;
  user = config.spaceElevator.user.name;
in
{
  options.spaceElevator.gaming.handheld = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Handheld Daemon for a handheld gaming PC: the built-in gamepad
        appears to Steam as a controller (a DualSense Edge by default),
        the vendor buttons open its overlay, and it owns TDP presets,
        fan curves, charge limits and RGB. Also adds the Big Picture
        session and, unless autoLogin is off, boots straight into it.
      '';
    };

    autoLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Boot straight into the Big Picture session as
        spaceElevator.user.name, the way a console does. Exit Steam
        from its power menu to reach the login screen and pick the
        desktop instead. Off means the login screen comes up first.
      '';
    };

    acpiCall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load the out-of-tree acpi_call module, which Handheld Daemon
        uses for TDP control on the Legion Go, GPD and AYANEO devices.
        The ROG Ally and Steam Deck have in-kernel drivers and do not
        need it; turn this off there if a kernel bump stops it building.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = user != null;
        message = ''
          spaceElevator.gaming.handheld needs spaceElevator.user.name:
          Handheld Daemon runs as that user.
        '';
      }
      {
        assertion = config.spaceElevator.gaming.steam.enable;
        message = ''
          spaceElevator.gaming.handheld needs spaceElevator.gaming.steam:
          the Big Picture session it boots into is Steam's.
        '';
      }
      {
        assertion = cfg.autoLogin -> config.spaceElevator.gaming.steam.gamescopeSession;
        message = ''
          spaceElevator.gaming.handheld.autoLogin boots into the Big
          Picture session, which gaming.steam.gamescopeSession = false
          removed. Turn one of the two around.
        '';
      }
      {
        assertion = config.spaceElevator.base.kernel != "default";
        message = ''
          spaceElevator.gaming.handheld needs base.kernel = "latest"
          (or zen / xanmod): TDP control on the ROG Ally comes from the
          asus-armoury driver in Linux 6.19+, and the release kernel is
          older.
        '';
      }
      {
        assertion = !config.spaceElevator.tuning.tlp.enable;
        message = ''
          spaceElevator.gaming.handheld and spaceElevator.tuning.tlp both
          manage power profiles and charge limits; turn TLP off on a
          handheld.
        '';
      }
    ];

    services.handheld-daemon = lib.mkIf (user != null) {
      enable = true;
      inherit user;
      adjustor = {
        enable = true;
        loadAcpiCallModule = cfg.acpiCall;
      };
    };

    # Handheld Daemon serves the power-profiles D-Bus interface itself,
    # so the desktop's profile switcher drives its TDP presets, and it
    # disables that part of itself while power-profiles-daemon runs.
    services.power-profiles-daemon.enable = false;

    spaceElevator.gaming.steam.gamescopeSession = lib.mkDefault true;

    services.displayManager = lib.mkIf (cfg.autoLogin && user != null) {
      autoLogin = {
        enable = true;
        inherit user;
      };
      defaultSession = "steam";
    };
  };
}
