# modules/gpu/default.nix — graphics drivers.
#
# The wizard enables the one it detects. On a hybrid laptop you want
# the discrete card's module (nvidia/amd) plus PRIME; see nvidia.nix.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.gpu;
in
{
  imports = [
    ./amd.nix
    ./intel.nix
    ./nvidia.nix
  ];

  config.assertions = [
    {
      assertion = !(cfg.amd.enable && cfg.nvidia.enable);
      message = ''
        Space Elevator: spaceElevator.gpu.amd and spaceElevator.gpu.nvidia
        are both enabled. For an AMD iGPU + NVIDIA dGPU laptop, enable
        nvidia only and set spaceElevator.gpu.nvidia.prime.amdgpuBusId —
        the NVIDIA module brings up the Mesa side for you.
      '';
    }
  ];
}
