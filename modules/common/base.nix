# modules/common/base.nix
# Generic core: flakes, kernel choice, unfree, polkit, firmware updates.
# No inputs dependency.
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.base;
  nvidia = config.spaceElevator.gpu.nvidia;

  kernels = {
    latest = pkgs.linuxPackages_latest;
    default = pkgs.linuxPackages;
    zen = pkgs.linuxPackages_zen;
    xanmod = pkgs.linuxPackages_xanmod_latest;
  };
in
{
  options.spaceElevator.base = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.enable;
      defaultText = lib.literalExpression "config.spaceElevator.enable";
      description = ''
        Core system settings: flakes, the kernel, unfree packages,
        polkit, firmware updates and periodic TRIM. Effectively
        mandatory — the rest of the module set assumes it.
      '';
    };

    kernel = lib.mkOption {
      type = lib.types.enum [
        "latest"
        "default"
        "zen"
        "xanmod"
      ];
      default = if nvidia.enable && nvidia.pinKernel then "default" else "latest";
      defaultText = lib.literalExpression ''"default" when the NVIDIA driver pins the kernel, otherwise "latest"'';
      description = ''
        Which kernel to boot.

        - latest: newest mainline. The default, and the reason the
          NVIDIA module moves it: mainline periodically outruns
          driver support.
        - default: the release's own kernel — older, and always a
          supported pairing with the NVIDIA driver.
        - zen: mainline plus the Zen patch set, tuned for desktop
          latency under load. Usually the best feel for games.
        - xanmod: mainline plus Xanmod's patches, same idea.

        Zen and Xanmod are out-of-tree builds, so they lag mainline by
        a few days after a `nix flake update` and are one more thing
        that can fail to build. Worth it on a machine you game on;
        think twice on one you depend on.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = lib.mkDefault kernels.${cfg.kernel};

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
  };
}
