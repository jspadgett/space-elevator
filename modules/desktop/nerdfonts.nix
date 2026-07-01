# modules/desktop/nerdfonts.nix
# Common Nerd Fonts for terminals and bars
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    nerd-fonts.hack
    noto-fonts
    noto-fonts-color-emoji
  ];
}
