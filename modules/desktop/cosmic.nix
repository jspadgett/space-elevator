# modules/desktop/cosmic.nix
# System76 COSMIC desktop
{ pkgs, ... }:
{
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  # App store (Flatpak/Flathub backend works out of the box on NixOS)
  environment.systemPackages = [ pkgs.cosmic-store ];
}
