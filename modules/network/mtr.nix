# modules/features/mtr.nix
# mtr network diagnostic with setuid wrapper
{ ... }:
{
  programs.mtr.enable = true;
}
