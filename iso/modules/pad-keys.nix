# iso/modules/pad-keys.nix — a gamepad drives the installer console.
#
# pad-keys turns any connected pad into a keyboard: D-pad and left
# stick are the arrow keys, A/Start is Enter, B/Select is Escape, X is
# Space, Y is Tab. While a pad is connected it keeps /run/pad-keys/pad
# in place, and the wizard then answers its text prompts with
# pad-type, an on-screen keyboard driven by those same keys.
#
# ISO only. On an installed system Handheld Daemon owns the pad.
{ pkgs, ... }:
let
  pad-keys = pkgs.writers.writePython3Bin "pad-keys" {
    libraries = [ pkgs.python3Packages.evdev ];
  } (builtins.readFile ./pad-keys.py);

  pad-type = pkgs.writers.writePython3Bin "pad-type" { } (builtins.readFile ./pad-type.py);
in
{
  # The virtual keyboard is a uinput device.
  boot.kernelModules = [ "uinput" ];

  # The wizard finds pad-type on PATH.
  environment.systemPackages = [ pad-type ];

  systemd.services.pad-keys = {
    description = "Gamepad as keyboard for the installer console";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pad-keys}/bin/pad-keys";
      Restart = "always";
      RestartSec = 2;
      # /run/pad-keys, created for the marker and removed with the service.
      RuntimeDirectory = "pad-keys";
    };
  };
}
