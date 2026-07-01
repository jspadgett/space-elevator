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
  environment.systemPackages = with pkgs; [ mangohud ];
}
