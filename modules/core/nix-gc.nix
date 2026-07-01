# modules/features/nix-gc.nix
# Automatic garbage collection + store deduplication
{ ... }:
{
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    settings.auto-optimise-store = true;
  };
}
