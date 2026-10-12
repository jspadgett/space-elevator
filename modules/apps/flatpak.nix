# modules/apps/flatpak.nix
# Flatpak with the Flathub remote added on activation. This is what
# makes each desktop's app store useful out of the box.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.apps.flatpak;
  flatpak = "${config.services.flatpak.package}/bin/flatpak";
in
{
  options.spaceElevator.apps.flatpak.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.spaceElevator.desktop.enable;
    defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
    description = ''
      Flatpak, with Flathub configured so Discover / GNOME Software /
      COSMIC Store can install apps without editing any config.
    '';
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;

    # Adding Flathub downloads its repo metadata, so it needs the
    # network. The timer starts the service once per boot, outside the
    # boot transaction: an offline first boot reaches the desktop
    # without waiting on it, and the service keeps retrying until the
    # remote is added. Once Flathub exists, later runs exit at the
    # ExecCondition without touching the network.
    systemd.timers.flatpak-repo = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnBootSec = "15s";
    };

    systemd.services.flatpak-repo = {
      description = "Add the Flathub remote to Flatpak";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # Retry indefinitely: StartLimitIntervalSec=0 stops systemd from
      # giving up after a burst of failures.
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        ExecCondition = "/bin/sh -c '! ${flatpak} remotes --system --columns=name | grep -qx flathub'";
        ExecStart = "${flatpak} remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo";
        Restart = "on-failure";
        RestartSec = "1min";
      };
    };
  };
}
