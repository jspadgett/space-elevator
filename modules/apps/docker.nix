# modules/features/docker.nix
# Docker with weekly prune. Add your user to the "docker" group manually
# if you accept the root-equivalence tradeoff; otherwise use rootless mode.
{ ... }:
{
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
