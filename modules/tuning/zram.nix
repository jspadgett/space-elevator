# modules/tuning/zram.nix
# Compressed RAM swap - fast, good default for desktops.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.tuning.zram;
in
{
  options.spaceElevator.tuning.zram = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.tuning.enable;
      defaultText = lib.literalExpression "config.spaceElevator.tuning.enable";
      description = ''
        Compressed swap in RAM. For heavy source compilation
        (Electron, qtwebengine) pair it with a real swapfile.
      '';
    };

    memoryPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 50;
      description = "Share of RAM the compressed swap device may grow to.";
    };
  };

  config = lib.mkIf cfg.enable {
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      inherit (cfg) memoryPercent;
    };
  };
}
