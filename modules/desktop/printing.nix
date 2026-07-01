# modules/desktop/printing.nix
# CUPS printing with network printer discovery
{ ... }:
{
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
