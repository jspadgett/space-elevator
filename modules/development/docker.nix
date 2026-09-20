# modules/development/docker.nix
# Docker with weekly prune. Add your user to the "docker" group
# manually if you accept the root-equivalence tradeoff; otherwise use
# rootless mode.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.development.docker;
in
{
  options.spaceElevator.development.docker = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.development.enable;
      defaultText = lib.literalExpression "config.spaceElevator.development.enable";
      description = "The Docker daemon.";
    };

    autoPrune = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prune unused images and containers weekly.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = cfg.autoPrune;
        dates = "weekly";
      };
    };
  };
}
