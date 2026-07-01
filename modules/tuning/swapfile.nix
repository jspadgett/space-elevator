# modules/features/swapfile.nix
# Disk-backed swapfile. Prevents OOM kills during large builds
# (Electron, qtwebengine, LLVM). Complements zram: zram absorbs everyday
# pressure at RAM speed, the swapfile is the deep reserve for compiles.
{ ... }:
{
  swapDevices = [{
    device = "/var/lib/swapfile";
    size = 32 * 1024; # MiB - adjust to taste (32 GiB default)
  }];
}
