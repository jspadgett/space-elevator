# modules/desktop/bluetooth.nix
# Bluetooth with Blueman applet
{ ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      Experimental = true; # battery reporting
      FastConnectable = true;
    };
  };
  services.blueman.enable = true;
}
