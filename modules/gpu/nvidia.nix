# modules/gpu/nvidia.nix
# NVIDIA proprietary driver, for both desktops (the card drives the
# display) and hybrid laptops (the iGPU drives the panel and the dGPU
# renders on demand via PRIME offload).
#
# Hybrid laptop, in your host's space-elevator.nix:
#
#   spaceElevator.gpu.nvidia = {
#     enable = true;
#     prime = {
#       enable = true;
#       intelBusId  = "PCI:0:2:0";   # or amdgpuBusId on an AMD iGPU
#       nvidiaBusId = "PCI:1:0:0";
#     };
#   };
#
# Bus IDs come from `lspci | grep -E 'VGA|3D'`, converted to NixOS's
# decimal "PCI:bus:device:function" form:
#   00:02.0 -> "PCI:0:2:0"      01:00.0 -> "PCI:1:0:0"
#   0a:00.0 -> "PCI:10:0:0"     (hex -> decimal!)
{ config, lib, pkgs, ... }:
let
  cfg = config.spaceElevator.gpu.nvidia;
  isLegacy = lib.hasPrefix "legacy_" cfg.driver;
  igpuBusIds = lib.filter (id: id != null) [ cfg.prime.intelBusId cfg.prime.amdgpuBusId ];

  # Rejects the hex form lspci prints, with an error that says so.
  busId = lib.types.strMatching "PCI:[0-9]+:[0-9]+:[0-9]+" // {
    description = ''a decimal PCI bus ID such as "PCI:1:0:0" (lspci prints hex: 01:00.0)'';
  };
in
{
  options.spaceElevator.gpu.nvidia = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "The proprietary NVIDIA driver, with 32-bit support for games.";
    };

    driver = lib.mkOption {
      type = lib.types.enum [ "stable" "beta" "production" "latest" "legacy_580" "legacy_470" ];
      default = "stable";
      description = ''
        Which driver branch to use. In nixos-26.05 `stable` is the 595
        series, which dropped Maxwell, Pascal and Volta — on a GTX 10xx
        or 9xx card use "legacy_580" instead (and leave `open` off).
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = config.boot.kernelPackages.nvidiaPackages.${cfg.driver};
      defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.\${driver}";
      description = "The driver package itself. Set this to override the `driver` branch selection.";
    };

    open = lib.mkOption {
      type = lib.types.bool;
      default = !isLegacy;
      defaultText = lib.literalExpression "not a legacy driver branch";
      description = ''
        Use the open kernel modules. Required on Turing and newer
        (GTX 16xx, RTX 20xx and up); unsupported on older cards.
      '';
    };

    pinKernel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Ask for the release's own kernel rather than the newest
        mainline one. The newest mainline kernel periodically outruns
        NVIDIA driver support, which turns `nix flake update` into a
        broken boot; the default kernel is always a driver-supported
        pairing.

        This moves the default of spaceElevator.base.kernel rather
        than forcing it — set that option explicitly and your choice
        wins, with a warning.
      '';
    };

    powerManagement = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Driver-side suspend/resume handling. Without it the dGPU
          never powers down properly — battery drain, and corruption
          after sleep.
        '';
      };

      finegrained = lib.mkOption {
        type = lib.types.bool;
        default = cfg.prime.enable;
        defaultText = lib.literalExpression "config.spaceElevator.gpu.nvidia.prime.enable";
        description = ''
          Runtime D3: power the dGPU down entirely while nothing is
          using it. Turing and newer only, and requires PRIME offload.
        '';
      };
    };

    prime = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Hybrid graphics: the iGPU drives the display and the NVIDIA
          card renders on demand. Adds the `nvidia-offload` wrapper —
          prefix a command with it to run that program on the dGPU.
        '';
      };

      offloadCmd = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the `nvidia-offload` command wrapper.";
      };

      intelBusId = lib.mkOption {
        type = lib.types.nullOr busId;
        default = null;
        example = "PCI:0:2:0";
        description = "Bus ID of the Intel iGPU. Mutually exclusive with amdgpuBusId.";
      };

      amdgpuBusId = lib.mkOption {
        type = lib.types.nullOr busId;
        default = null;
        example = "PCI:5:0:0";
        description = "Bus ID of the AMD iGPU. Mutually exclusive with intelBusId.";
      };

      nvidiaBusId = lib.mkOption {
        type = lib.types.nullOr busId;
        default = null;
        example = "PCI:1:0:0";
        description = "Bus ID of the NVIDIA dGPU.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.prime.enable -> (cfg.prime.nvidiaBusId != null && igpuBusIds != [ ]);
        message = ''
          spaceElevator.gpu.nvidia.prime needs bus IDs: nvidiaBusId plus
          exactly one of intelBusId / amdgpuBusId. Find them with
          `lspci | grep -E 'VGA|3D'` and convert to decimal
          "PCI:bus:device:function" (01:00.0 -> "PCI:1:0:0").
        '';
      }
      {
        assertion = lib.length igpuBusIds <= 1;
        message = ''
          spaceElevator.gpu.nvidia.prime: set intelBusId or amdgpuBusId,
          never both — they describe the same thing, the integrated GPU
          that drives the panel.
        '';
      }
      {
        assertion = cfg.powerManagement.finegrained -> cfg.prime.enable;
        message = ''
          spaceElevator.gpu.nvidia.powerManagement.finegrained (runtime
          D3) only applies to a hybrid laptop; it requires
          spaceElevator.gpu.nvidia.prime.enable.
        '';
      }
      {
        assertion = !(cfg.open && isLegacy);
        message = ''
          spaceElevator.gpu.nvidia: the open kernel modules do not
          support the ${cfg.driver} branch. Set `open = false;`.
        '';
      }
    ];

    # The kernel itself is chosen in one place, spaceElevator.base.kernel,
    # whose default follows pinKernel. Say something if the two disagree.
    warnings = lib.optional (cfg.pinKernel && config.spaceElevator.base.kernel != "default") ''
      spaceElevator.gpu.nvidia.pinKernel is on, but
      spaceElevator.base.kernel is set to "${config.spaceElevator.base.kernel}".
      Your choice stands — just know that this is the pairing that
      breaks: a kernel newer than the NVIDIA driver supports will fail
      to build, usually right after `nix flake update`. If it does,
      switch to "default" and rebuild.
    '';

    # nixpkgs refuses to build the driver until its licence is
    # accepted. Turning this module on is that acceptance:
    # https://www.nvidia.com/content/DriverDownloads/licence.php?lang=us
    nixpkgs.config.nvidia.acceptLicense = true;

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # Required for the NixOS nvidia module to load the driver at all,
    # even on Wayland. With PRIME offload, Xorg (if used) gets an
    # iGPU + NVIDIA layout instead of NVIDIA-only.
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # KMS: needed for Wayland sessions and for GDM to stay on Wayland.
      modesetting.enable = true;
      nvidiaSettings = true;

      inherit (cfg) open package;

      powerManagement = {
        inherit (cfg.powerManagement) enable finegrained;
      };

      prime = lib.mkIf cfg.prime.enable (
        {
          offload.enable = true;
          offload.enableOffloadCmd = cfg.prime.offloadCmd;
        }
        // lib.optionalAttrs (cfg.prime.intelBusId != null) { inherit (cfg.prime) intelBusId; }
        // lib.optionalAttrs (cfg.prime.amdgpuBusId != null) { inherit (cfg.prime) amdgpuBusId; }
        // lib.optionalAttrs (cfg.prime.nvidiaBusId != null) { inherit (cfg.prime) nvidiaBusId; }
      );
    };
  };
}
