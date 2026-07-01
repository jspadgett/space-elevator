# modules/desktop/gnome.nix
# GNOME with GDM
{ ... }:
{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
}
