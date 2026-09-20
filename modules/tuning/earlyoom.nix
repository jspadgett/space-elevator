# modules/tuning/earlyoom.nix
# Kills the largest process before a full OOM freeze locks the machine
{ config, lib, ... }:
let
  cfg = config.spaceElevator.tuning.earlyoom;
in
{
  options.spaceElevator.tuning.earlyoom.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.tuning.enable;
    defaultText = lib.literalExpression "config.spaceElevator.tuning.enable";
    description = ''
      earlyoom: kills the biggest memory hog while the machine is still
      responsive, instead of letting it thrash to a standstill.
    '';
  };

  config = lib.mkIf cfg.enable {
    services.earlyoom = {
      enable = true;
      freeMemThreshold = 5;  # act at 5% free RAM
      freeSwapThreshold = 10;
    };
  };
}
