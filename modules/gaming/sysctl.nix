# modules/gaming/sysctl.nix
# Kernel settings that games, specifically, need.
#
# Both of these are what SteamOS, CachyOS and Nobara set. They cost
# nothing on a machine that isn't gaming, which is why they are part
# of the gaming baseline rather than a question.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.gaming.sysctl;
in
{
  options.spaceElevator.gaming.sysctl = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.gaming.enable;
      defaultText = lib.literalExpression "config.spaceElevator.gaming.enable";
      description = "Kernel tunables that games depend on.";
    };

    maxMapCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2147483642;
      description = ''
        vm.max_map_count — how many memory mappings one process may
        hold. NixOS defaults to 1048576, which a handful of big
        titles (Star Citizen, Hogwarts Legacy, DayZ) exhaust; they
        then crash in ways that look like anything but a limit. This
        is the value Valve ships on the Steam Deck.
      '';
    };

    splitLockMitigate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        kernel.split_lock_mitigate — the kernel penalises processes
        that perform split locks, and several games (and Wine itself)
        do, which shows up as stutter. Off here, as on every other
        gaming distribution; turn it back on if you would rather have
        the protection from a misbehaving process.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl = {
      "vm.max_map_count" = cfg.maxMapCount;
      "kernel.split_lock_mitigate" = if cfg.splitLockMitigate then 1 else 0;
    };
  };
}
