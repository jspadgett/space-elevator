# modules/desktop/bluetooth.nix
# Bluetooth with Blueman applet
{ config, lib, ... }:
let
  cfg = config.spaceElevator.desktop.bluetooth;
in
{
  options.spaceElevator.desktop.bluetooth.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = "Bluetooth, powered on at boot, with the Blueman applet.";
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General = {
        Experimental = true; # battery reporting
        FastConnectable = true;
      };
    };
    services.blueman.enable = true;
  };
}
