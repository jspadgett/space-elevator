# modules/desktop/printing.nix
# CUPS printing with network printer discovery
{ config, lib, ... }:
let
  cfg = config.spaceElevator.desktop.printing;
in
{
  options.spaceElevator.desktop.printing.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = ''
      CUPS printing, plus Avahi so network printers show up on their
      own (this opens the mDNS port on the firewall).
    '';
  };

  config = lib.mkIf cfg.enable {
    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
