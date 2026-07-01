# modules/features/firewall.nix
# Drop-by-default firewall. Add ports per-host as needed:
#   networking.firewall.allowedTCPPorts = [ 8080 ];
{ ... }:
{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };
}
