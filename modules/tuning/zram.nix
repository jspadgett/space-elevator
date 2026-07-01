# modules/features/zram.nix
# Compressed RAM swap - fast, good default for desktops.
# For heavy source compilation (Electron, qtwebengine) pair with swapfile.nix.
{ ... }:
{
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
