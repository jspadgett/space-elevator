# modules/gaming/rgb.nix
# OpenRGB: control the lighting on motherboards, RAM, fans, keyboards
# and mice from one place, instead of one vendor app per device.
#
# Off by default: it needs the i2c kernel modules loaded to reach
# motherboard and RAM controllers, and that is not a thing to do to a
# machine uninvited.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.gaming.rgb;
in
{
  options.spaceElevator.gaming.rgb.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      OpenRGB, with the i2c modules it needs to see motherboard and
      memory lighting. USB devices (keyboards, mice, some fan hubs)
      work without them.
    '';
  };

  config = lib.mkIf cfg.enable {
    # The nixpkgs module loads the right i2c driver on its own, from
    # whichever CPU microcode your hardware-configuration.nix enables.
    services.hardware.openrgb.enable = true;
  };
}
