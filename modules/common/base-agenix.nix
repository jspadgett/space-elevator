# modules/common/base-agenix.nix
# Installs the agenix CLI. Only import when the agenix flake input exists.
{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    inputs.agenix.packages.${pkgs.system}.default
  ];
}
