# modules/gpu/nvidia.nix
# NVIDIA proprietary driver — hybrid laptop layout (iGPU drives the panel,
# NVIDIA dGPU renders on demand via PRIME offload).
#
# FILL IN before installing: intelBusId / nvidiaBusId (see PRIME below).
{ config, pkgs, ... }:
{
  # Stability: the newest mainline kernel periodically outruns NVIDIA
  # driver support, which breaks `nix flake update`. The default kernel
  # is always a driver-supported pairing. (Overrides base's mkDefault.)
  boot.kernelPackages = pkgs.linuxPackages;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Required for the NixOS nvidia module to load the driver at all,
  # even on Wayland. With PRIME offload below, Xorg (if used) gets an
  # iGPU + NVIDIA layout instead of NVIDIA-only.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # KMS: needed for Wayland sessions and for GDM to stay on Wayland.
    modesetting.enable = true;
    nvidiaSettings = true;

    # ── Driver + kernel module ─────────────────────────────────────
    # Turing or newer (GTX 16xx, RTX 20xx–50xx): open modules + stable.
    # In nixos-26.05 `stable` = 595.x, which dropped Maxwell/Pascal/Volta.
    #
    # Pre-Turing (GTX 10xx / 9xx) — replace these two lines with:
    #   open = false;
    #   package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    # and delete powerManagement.finegrained below.
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # ── Power ──────────────────────────────────────────────────────
    # enable: driver-side suspend/resume handling — without it the dGPU
    # never powers down (battery drain, corruption after sleep).
    # finegrained: runtime D3 for the dGPU when idle. Turing+ only;
    # the nixpkgs module asserts this requires prime.offload.
    powerManagement.enable = true;
    powerManagement.finegrained = true;

    # ── PRIME (hybrid graphics) ────────────────────────────────────
    # Bus IDs from:  lspci | grep -E 'VGA|3D'
    # NixOS wants decimal "PCI:bus:device:function":
    #   00:02.0 → "PCI:0:2:0"      01:00.0 → "PCI:1:0:0"
    #   0a:00.0 → "PCI:10:0:0"     (hex → decimal!)
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # `nvidia-offload <cmd>` wrapper

      intelBusId  = "PCI:0:2:0";  # AMD iGPU laptop: remove this line and
      # amdgpuBusId = "PCI:x:x:x";  # use amdgpuBusId instead (never both)
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}

