# modules/gaming/gamemode.nix
# Feral GameMode + MangoHud overlay
{ config, pkgs, ... }:
{
  programs.gamemode = {
    enable = true;
    settings.general = {
      renice = 10;
      inhibit_screensaver = 1;
    };
  };
  # renice only works for members of the gamemode group
  users.users.${config.spaceElevator.user.name}.extraGroups = [ "gamemode" ];

  environment.systemPackages = with pkgs; [ mangohud ];
}
