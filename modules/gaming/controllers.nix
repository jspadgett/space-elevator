# modules/gaming/controllers.nix
# Game controllers and gaming peripherals.
#
# Steam's own module installs the steam-hardware udev rules, which
# cover the Steam Controller, the Steam Deck and wired Xbox pads. This
# module covers everything else, so a pad works whether or not the
# game came from Steam.
#
# xpadneo and xone are out-of-tree kernel modules: if one ever fails
# to build after a kernel bump, switch it off here and rebuild while
# upstream catches up.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gaming.controllers;
in
{
  options.spaceElevator.gaming.controllers = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.gaming.enable;
      defaultText = lib.literalExpression "config.spaceElevator.gaming.enable";
      description = "Driver and permission support for game controllers.";
    };

    xpadneo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Xbox controllers over Bluetooth, with rumble and correct
        button mapping (the in-tree driver gets both wrong).
      '';
    };

    xone = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The Xbox Wireless Adapter — the USB dongle that came with
        Xbox One pads — plus newer wired Xbox pads. Replaces the
        in-tree xpad driver with xpad-noone, which is what lets the
        two coexist.
      '';
    };

    udevRules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Permissions for the controllers nobody else covers: PlayStation
        (DualShock and DualSense), Nintendo Switch pads, 8BitDo and the
        rest. Without these a pad is visible to the kernel but not to
        the games that would use it.
      '';
    };

    mice = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        ratbagd and Piper: on-board DPI, polling rate, button mapping
        and lighting for gaming mice (Logitech, SteelSeries, Razer and
        others). Off by default — it is only useful if you own one of
        the supported mice.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.xpadneo.enable = cfg.xpadneo;
    hardware.xone.enable = cfg.xone;

    services.udev.packages = lib.optionals cfg.udevRules [ pkgs.game-devices-udev-rules ];

    services.ratbagd.enable = cfg.mice;
    environment.systemPackages = lib.optionals cfg.mice [ pkgs.piper ];
  };
}
