# modules/features/nvidia.nix
# NVIDIA proprietary driver (Turing or newer recommended).
# For laptops with hybrid graphics, add PRIME offload config per the NixOS wiki.
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
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = true; # open kernel module; set false for pre-Turing cards
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
