# modules/desktop/hyprland.nix
# Hyprland Wayland compositor with greetd/tuigreet login
{ pkgs, ... }:
{
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
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
  ];
}
