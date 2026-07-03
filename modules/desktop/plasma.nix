# modules/desktop/plasma.nix
# KDE Plasma 6 with SDDM
{ pkgs, ... }:
{
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # App store (Flatpak/Flathub backend works out of the box on NixOS)
  environment.systemPackages = [ pkgs.kdePackages.discover ];
}
