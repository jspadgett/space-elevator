# modules/tuning/default.nix — housekeeping and system sanity.
#
# These are the "every distro does this for you" bits: swap, an OOM
# killer that acts before the machine freezes, garbage collection, and
# tooling for working on a flake-based system. All on by default.
{ config, lib, ... }:
{
  imports = [
    ./earlyoom.nix
    ./nix-gc.nix
    ./nix-tools.nix
    ./tlp.nix
    ./zram.nix
  ];

  options.spaceElevator.tuning.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.enable;
    defaultText = lib.literalExpression "config.spaceElevator.enable";
    description = ''
      Sets the default for the housekeeping options below (zram,
      earlyoom, garbage collection, Nix tooling). TLP is the exception:
      it is laptop-specific and stays off unless asked for.
    '';
  };
}
