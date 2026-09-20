# modules/apps/flatpak.nix
# Flatpak with the Flathub remote added on activation. This is what
# makes each desktop's app store useful out of the box.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.apps.flatpak;
in
{
  options.spaceElevator.apps.flatpak.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = ''
      Flatpak, with Flathub configured so Discover / GNOME Software /
      COSMIC Store can install apps without editing any config.
    '';
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;
    systemd.services.flatpak-repo = {
      wantedBy = [ "multi-user.target" ];
      path = [ ];
      script = ''
        /run/current-system/sw/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      '';
    };
  };
}
