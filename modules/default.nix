# modules/default.nix — the Space Elevator module set.
#
# Import this directory once and every feature below becomes available
# as an option. Nothing turns on until `spaceElevator.enable = true;`,
# and from there each feature is a single `enable` line.
#
#   spaceElevator = {
#     enable = true;
#     user = "alice";
#     desktop.plasma.enable = true;
#     gaming.enable = true;
#   };
#
# Option paths mirror the directory layout (desktop/audio.nix declares
# spaceElevator.desktop.audio), with one exception: common/ holds the
# foundations, which sit at spaceElevator.base and spaceElevator.locale.
{ lib, ... }:
{
  imports = [
    ./common
    ./desktop
    ./network
    ./apps
    ./gaming
    ./development
    ./gpu
    ./tuning
  ];

  options.spaceElevator = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Master switch for the Space Elevator module set. Turns on the
        baseline every generated desktop gets (core system settings,
        networking, housekeeping) and lets the per-feature defaults
        below follow along. Importing the modules without this does
        nothing at all.
      '';
    };

    user.name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        Primary user of this machine. Features that need a specific
        account — group membership for GameMode, for instance — use
        this. Setting it does not create the user; declare that in the
        host's own configuration.nix as usual.
      '';
    };
  };
}
