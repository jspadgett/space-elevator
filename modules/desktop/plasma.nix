# modules/desktop/plasma.nix
# KDE Plasma 6 with SDDM — the flavor: session, login manager, app
# store and the KDE apps that make it feel like a complete desktop.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.desktop.plasma;
in
{
  options.spaceElevator.desktop.plasma.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      KDE Plasma 6 on Wayland with SDDM, the Discover app store and the
      core KDE applications. Enabling any desktop also turns on the
      shared desktop plumbing (see spaceElevator.desktop.enable).
    '';
  };

  config = lib.mkIf cfg.enable {
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };

    environment.systemPackages = with pkgs.kdePackages; [
      discover   # app store (Flatpak/Flathub backend works out of the box)
      kate       # editor
      kcalc
      filelight  # disk usage
    ];

    # Elisa duplicates mpv from the common set; drop it.
    environment.plasma6.excludePackages = [ pkgs.kdePackages.elisa ];
  };
}
