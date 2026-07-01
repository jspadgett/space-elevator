# modules/features/earlyoom.nix
# Kills the largest process before a full OOM freeze locks the machine
{ ... }:
{
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;  # act at 5% free RAM
    freeSwapThreshold = 10;
  };
}
