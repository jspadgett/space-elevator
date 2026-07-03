# modules/desktop/gnome.nix
# GNOME with GDM
{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # App store (Flatpak/Flathub backend works out of the box on NixOS)
  environment.systemPackages = [ pkgs.gnome-software ];
}
