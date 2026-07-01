# modules/features/auto-upgrade.nix
# Weekly automatic rebuild from your flake. Set your flake URI below.
{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos"; # CHANGE ME: path or github: URI of your flake
    dates = "weekly";
    operation = "boot"; # applied on next reboot; use "switch" for immediate
    allowReboot = false;
  };
}
