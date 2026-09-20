# modules/desktop/audio.nix
# PipeWire audio stack (replaces PulseAudio)
{ config, lib, ... }:
let
  cfg = config.spaceElevator.desktop.audio;
in
{
  options.spaceElevator.desktop.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = "PipeWire, with ALSA, PulseAudio and JACK compatibility.";
  };

  config = lib.mkIf cfg.enable {
    security.rtkit.enable = true;
    services.pulseaudio.enable = false;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };
}
