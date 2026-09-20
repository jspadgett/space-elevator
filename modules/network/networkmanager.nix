# modules/network/networkmanager.nix
# NetworkManager: Wi-Fi and wired networking with a GUI/TUI front end.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.network.networkmanager;
in
{
  options.spaceElevator.network.networkmanager.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.enable;
    defaultText = lib.literalExpression "config.spaceElevator.enable";
    description = ''
      NetworkManager. Remember to put the primary user in the
      "networkmanager" group so they can manage connections.
    '';
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.enable = true;
  };
}
