# modules/gaming/default.nix — gaming, which is the point of the
# distro and therefore part of the baseline.
#
# Every desktop gets Steam and GameMode without being asked. Opting
# out is:
#
#   spaceElevator.gaming.enable = false;
#
# and each piece underneath can still be switched off on its own.
{ config, lib, ... }:
{
  imports = [
    ./steam.nix
    ./gamemode.nix
    ./controllers.nix
    ./launchers.nix
    ./sysctl.nix
    ./rgb.nix
    ./streaming.nix
  ];

  options.spaceElevator.gaming.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = ''
      Steam (with Proton-GE, gamescope and protontricks), GameMode,
      MangoHud, the non-Steam launchers, controller drivers and the
      kernel tunables games need. On by default wherever there is a
      desktop to play on; sets the default for every option under
      spaceElevator.gaming.

      Game streaming (streaming) and RGB control (rgb) are the
      exceptions — they stay off until asked for.
    '';
  };
}
