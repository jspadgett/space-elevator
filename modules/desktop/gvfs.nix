# modules/desktop/gvfs.nix
# Virtual filesystem support (network shares, MTP devices in file
# managers) and automounting of removable drives.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.desktop.gvfs;
in
{
  options.spaceElevator.desktop.gvfs.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = ''
      gvfs and udisks2: network shares and phones (MTP) in file
      managers, and USB drives that mount when you plug them in.
    '';
  };

  config = lib.mkIf cfg.enable {
    services.gvfs.enable = true;
    services.udisks2.enable = true;
  };
}
