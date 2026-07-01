# modules/features/signal.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ signal-desktop ];
}
