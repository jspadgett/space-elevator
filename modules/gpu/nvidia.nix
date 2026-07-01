# modules/features/nvidia.nix
# NVIDIA proprietary driver (Turing or newer recommended).
# For laptops with hybrid graphics, add PRIME offload config per the NixOS wiki.
{ config, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = true; # open kernel module; set false for pre-Turing cards
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
