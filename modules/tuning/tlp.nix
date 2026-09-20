# modules/tuning/tlp.nix
# TLP laptop power management (do not combine with power-profiles-daemon)
{ config, lib, ... }:
let
  cfg = config.spaceElevator.tuning.tlp;
in
{
  options.spaceElevator.tuning.tlp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        TLP power management for laptops. Turns off
        power-profiles-daemon, which conflicts with it — so leave this
        off on a desktop, and off if you want your desktop's power
        profile switcher to work.
      '';
    };

    chargeThresholds = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          start = lib.mkOption {
            type = lib.types.ints.between 0 100;
            default = 40;
            description = "Start charging below this percentage.";
          };
          stop = lib.mkOption {
            type = lib.types.ints.between 0 100;
            default = 80;
            description = "Stop charging at this percentage.";
          };
        };
      });
      default = { };
      example = null;
      description = ''
        Battery charge thresholds for BAT0, which spare a
        permanently-docked laptop from sitting at 100%. Set to null to
        leave charging alone — not every battery supports thresholds,
        and on those TLP just logs a warning.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      }
      // lib.optionalAttrs (cfg.chargeThresholds != null) {
        START_CHARGE_THRESH_BAT0 = cfg.chargeThresholds.start;
        STOP_CHARGE_THRESH_BAT0 = cfg.chargeThresholds.stop;
      };
    };
    services.power-profiles-daemon.enable = false;
  };
}
