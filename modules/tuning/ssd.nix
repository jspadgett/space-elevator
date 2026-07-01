# modules/features/ssd.nix
# Periodic TRIM for SSDs
{ ... }:
{
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };
}
