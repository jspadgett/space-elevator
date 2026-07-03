# modules/common/base.nix
# Generic core: flakes, latest kernel, unfree, polkit, firmware updates.
# No inputs dependency.
{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Distro-standard housekeeping
  services.fwupd.enable = true;   # firmware updates (fwupdmgr)
  services.fstrim.enable = true;  # periodic TRIM; no-op on non-SSDs

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
