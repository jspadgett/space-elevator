# modules/desktop/desktop-packages.nix
# Everyday desktop applications
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    kitty
    mpv
    imv
    libreoffice
    file-roller
    pavucontrol
  ];
}
