# modules/tuning/nix-tools.nix
# Quality-of-life tooling for working on a flake-based system
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.tuning.nixTools;
in
{
  options.spaceElevator.tuning.nixTools.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.tuning.enable;
    defaultText = lib.literalExpression "config.spaceElevator.tuning.enable";
    description = "Nicer rebuilds, closure diffs, a formatter and a language server.";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      nh                 # nicer rebuild wrapper: `nh os switch`
      nvd                # closure diffs between generations
      nix-tree           # explore the dependency graph
      nix-output-monitor # `nom` - readable build output
      nixfmt             # formatter
      nil                # Nix language server
      git                # required for flakes anyway
    ];
  };
}
