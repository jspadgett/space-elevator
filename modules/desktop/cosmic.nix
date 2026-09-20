# modules/desktop/cosmic.nix
# System76 COSMIC desktop — the flavor: session, greeter and app store.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.desktop.cosmic;
in
{
  options.spaceElevator.desktop.cosmic.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      The COSMIC desktop from System76, with its greeter and the COSMIC
      Store. Enabling any desktop also turns on the shared desktop
      plumbing (see spaceElevator.desktop.enable).
    '';
  };

  config = lib.mkIf cfg.enable {
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    # App store (Flatpak/Flathub backend works out of the box on NixOS)
    environment.systemPackages = [ pkgs.cosmic-store ];
  };
}
