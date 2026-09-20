# modules/network/default.nix — connectivity and its front door.
{ ... }:
{
  imports = [
    ./networkmanager.nix
    ./firewall.nix
  ];
}
