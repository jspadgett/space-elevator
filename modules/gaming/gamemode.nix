# modules/features/gamemode.nix
# Feral GameMode + MangoHud overlay
{ pkgs, ... }:
{
  programs.gamemode = {
    enable = true;
    settings.general = {
      renice = 10;
      inhibit_screensaver = 1;
    };
  };
  # renice only works for members of the gamemode group
  users.users."@USERNAME@".extraGroups = [ "gamemode" ];

  environment.systemPackages = with pkgs; [ mangohud ];
}
