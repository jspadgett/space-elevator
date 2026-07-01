# modules/features/tailscale.nix
# Tailscale mesh VPN. Run `tailscale up` once after first boot.
{ ... }:
{
  services.tailscale.enable = true;
}
