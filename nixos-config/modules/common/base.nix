# modules/common/base.nix
# Generic core: flakes, latest kernel, unfree, polkit. No inputs dependency.
{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  security.polkit.enable = true;

  environment.systemPackages = with pkgs; [
    ffmpeg-headless      # video decoding for thumbnails
    ffmpegthumbnailer
  ];

  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];
}
