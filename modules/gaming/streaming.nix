# modules/gaming/streaming.nix
# Sunshine: turn this machine into a host you can stream games from,
# to a Moonlight client on a laptop, phone, TV or handheld.
#
# Off by default — it runs a service and opens ports, which is not
# something to do to someone who didn't ask.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.gaming.streaming;
in
{
  options.spaceElevator.gaming.streaming = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Sunshine, a game-streaming host for Moonlight clients. Pair a
        client at https://localhost:47990 after the first start.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the ports Moonlight needs. Streaming only works over the
        local network without this; turn it off if you intend to reach
        the host over a VPN instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      inherit (cfg) openFirewall;
      # Required for the virtual input device Moonlight drives the
      # session with (mouse, keyboard and virtual gamepad).
      capSysAdmin = true;
    };
  };
}
