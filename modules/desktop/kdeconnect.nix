# modules/desktop/kdeconnect.nix
# KDE Connect phone integration (opens required firewall ports).
# Part of the Plasma flavor; available to the others on request.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.desktop.kdeconnect;
in
{
  options.spaceElevator.desktop.kdeconnect.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.plasma.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.plasma.enable";
    description = ''
      KDE Connect: phone notifications, file transfer and remote input.
      Native to Plasma, so it follows that desktop by default — it
      works elsewhere too, it just brings KDE libraries along.
    '';
  };

  config = lib.mkIf cfg.enable {
    programs.kdeconnect.enable = true;
  };
}
