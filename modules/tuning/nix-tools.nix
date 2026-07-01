# modules/features/nix-tools.nix
# Quality-of-life tooling for working on a flake-based system
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nh                 # nicer rebuild wrapper: `nh os switch`
    nvd                # closure diffs between generations
    nix-tree           # explore the dependency graph
    nix-output-monitor # `nom` - readable build output
    nixfmt-rfc-style   # formatter
    nil                # Nix language server
    git                # required for flakes anyway
  ];
}
