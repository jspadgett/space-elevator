# modules/tuning/nix-gc.nix
# Automatic garbage collection + store deduplication
{ config, lib, ... }:
let
  cfg = config.spaceElevator.tuning.nixGc;
in
{
  options.spaceElevator.tuning.nixGc = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.tuning.enable;
      defaultText = lib.literalExpression "config.spaceElevator.tuning.enable";
      description = ''
        Collect garbage weekly and deduplicate the store, so old system
        generations don't quietly eat the disk.
      '';
    };

    keepDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = ''
        How many days of old generations to keep. Rollback only reaches
        as far back as this, so don't set it too low.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nix = {
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than ${toString cfg.keepDays}d";
      };
      settings.auto-optimise-store = true;
    };
  };
}
