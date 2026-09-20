# modules/desktop/gnome.nix
# GNOME with GDM — the flavor: session, login manager, app store,
# tweaks and extension support.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.desktop.gnome;
in
{
  options.spaceElevator.desktop.gnome.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      GNOME with GDM, the GNOME Software app store, Tweaks and browser
      support for extensions.gnome.org. Enabling any desktop also turns
      on the shared desktop plumbing (see spaceElevator.desktop.enable).
    '';
  };

  config = lib.mkIf cfg.enable {
    services.xserver.enable = true;
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Install extensions from extensions.gnome.org in the browser
    services.gnome.gnome-browser-connector.enable = true;

    environment.systemPackages = with pkgs; [
      gnome-software  # app store (Flatpak/Flathub backend works out of the box)
      gnome-tweaks
      dconf-editor
    ];

    # Shipped-by-default apps the common set already covers, or that
    # mostly get uninstalled on day one.
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany   # browser
      geary      # mail
      gnome-music
    ];
  };
}
