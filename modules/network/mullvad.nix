# modules/features/mullvad.nix
# Mullvad VPN with GUI
{ ... }:
{
  services.mullvad-vpn = {
    enable = true;
    enableExcludeWrapper = false;
  };
}
