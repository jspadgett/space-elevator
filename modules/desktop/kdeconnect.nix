# modules/features/kdeconnect.nix
# KDE Connect phone integration (opens required firewall ports)
{ ... }:
{
  programs.kdeconnect.enable = true;
}
