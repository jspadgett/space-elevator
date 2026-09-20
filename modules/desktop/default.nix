# modules/desktop/default.nix — desktop plumbing and the desktop
# environments themselves.
#
# Desktops are flavors: `spaceElevator.desktop.plasma.enable = true;`
# brings up the session, its login manager, its app store and the
# companion apps that desktop expects — and, because the plumbing
# below defaults to "a desktop is enabled", audio, Bluetooth, printing,
# fonts, removable media and the common application set come with it.
#
# The plumbing is deliberately identical whichever desktop you pick.
# Anything that differs belongs to the desktop's own module.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.desktop;

  # Every desktop environment this module set knows about. The list
  # drives both the "is any desktop on?" default and the one-at-a-time
  # assertion, so adding a desktop means adding it here and nowhere else.
  environments = [ "plasma" "gnome" "cosmic" "hyprland" ];
  enabled = lib.filter (de: cfg.${de}.enable) environments;
in
{
  imports = [
    ./audio.nix
    ./bluetooth.nix
    ./cosmic.nix
    ./fonts.nix
    ./gnome.nix
    ./gvfs.nix
    ./hyprland.nix
    ./kdeconnect.nix
    ./packages.nix
    ./plasma.nix
    ./printing.nix
    ./theming.nix
  ];

  options.spaceElevator.desktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.enable && enabled != [ ];
    defaultText = lib.literalExpression "a desktop environment is enabled";
    description = ''
      Desktop plumbing: audio, Bluetooth, printing, fonts, removable
      media and the everyday application set. On by default as soon as
      a desktop environment is selected; each piece can still be turned
      off individually.
    '';
  };

  config.assertions = [
    {
      assertion = lib.length enabled <= 1;
      message = ''
        Space Elevator: pick one desktop environment. Currently enabled:
        ${lib.concatMapStringsSep ", " (de: "spaceElevator.desktop.${de}") enabled}.
      '';
    }
  ];
}
