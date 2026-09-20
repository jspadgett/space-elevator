# modules/network/firewall.nix
# Drop-by-default firewall. Open ports per-host:
#   spaceElevator.network.firewall.allowedTCPPorts = [ 8080 ];
# Modules that need their own ports (Steam Remote Play, KDE Connect,
# printer discovery) open them themselves.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.network.firewall;
in
{
  options.spaceElevator.network.firewall = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.enable;
      defaultText = lib.literalExpression "config.spaceElevator.enable";
      description = "Firewall that drops incoming traffic unless a port is opened below.";
    };

    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      example = [ 8080 ];
      description = "Extra TCP ports to open on this host.";
    };

    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      example = [ 51820 ];
      description = "Extra UDP ports to open on this host.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = {
      enable = true;
      inherit (cfg) allowedTCPPorts allowedUDPPorts;
    };
  };
}
