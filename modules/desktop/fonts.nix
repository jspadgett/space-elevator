# modules/desktop/fonts.nix
# Common Nerd Fonts for terminals and bars, plus Noto for coverage
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.desktop.fonts;
in
{
  options.spaceElevator.desktop.fonts.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = "Nerd Fonts for terminals and status bars, Noto for everything else.";
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.hack
      noto-fonts
      noto-fonts-color-emoji
    ];
  };
}
