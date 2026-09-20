# modules/desktop/hyprland.nix
# Hyprland Wayland compositor — the flavor: compositor, greeter, bar,
# launcher, notifications, screenshots and a polkit agent, i.e. the
# pieces a full desktop environment would have given you.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.desktop.hyprland;
in
{
  options.spaceElevator.desktop.hyprland.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Hyprland with greetd/tuigreet, Waybar, wofi, dunst, screenshot
      tools, a file manager and a polkit agent. Enabling any desktop
      also turns on the shared desktop plumbing (see
      spaceElevator.desktop.enable).
    '';
  };

  config = lib.mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };

    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    environment.systemPackages = with pkgs; [
      waybar
      wofi
      dunst
      hyprpaper
      hyprlock
      hypridle
      grim
      slurp
      wl-clipboard
      nautilus         # file manager (Plasma/GNOME/COSMIC get theirs from the DE)
      hyprpolkitagent  # GUI auth prompts (needed for disk formatting etc.)
    ];

    # Start the polkit agent with the session so privileged GUI actions
    # (formatting drives, GParted, etc.) can prompt for authentication.
    systemd.user.services.hyprpolkitagent = {
      description = "Hyprland polkit authentication agent";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
      };
    };
  };
}
