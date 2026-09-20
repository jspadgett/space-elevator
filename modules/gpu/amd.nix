# modules/gpu/amd.nix
# AMD GPU (RADV/Mesa) with 32-bit support for gaming
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gpu.amd;
in
{
  options.spaceElevator.gpu.amd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "AMD graphics: Mesa/RADV with 32-bit support for games.";
    };

    lact = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "LACT, a GUI + daemon for fan curves, clocks and monitoring.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    environment.systemPackages = lib.optionals cfg.lact [ pkgs.lact ];

    systemd.services.lactd = lib.mkIf cfg.lact {
      description = "AMDGPU Control Daemon";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.lact}/bin/lact daemon";
    };
  };
}
