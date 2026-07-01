# modules/desktop/plasma.nix
# KDE Plasma 6 with SDDM
{ ... }:
{
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
}
