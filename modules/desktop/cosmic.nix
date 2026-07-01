# modules/desktop/cosmic.nix
# System76 COSMIC desktop
{ ... }:
{
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
}
