# modules/gpu/intel.nix
# Intel integrated graphics with VA-API acceleration
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gpu.intel;
in
{
  options.spaceElevator.gpu.intel.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Intel integrated graphics with hardware video decoding (VA-API)
      and 32-bit support for games.
    '';
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-compute-runtime
        libvdpau-va-gl
      ];
    };
    environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  };
}
