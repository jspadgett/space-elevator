# modules/features/gvfs.nix
# Virtual filesystem support (network shares, MTP devices in file managers)
{ ... }:
{
  services.gvfs.enable = true;
  services.udisks2.enable = true;
}
