# modules/common/default.nix — foundations every host wants.
{ ... }:
{
  imports = [
    ./base.nix
    ./locale.nix
  ];
}
