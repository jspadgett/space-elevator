# modules/development/default.nix — the development flavor.
#
#   spaceElevator.development.enable = true;
#
# turns on everything in this directory; each piece can still be
# switched off on its own.
{ config, lib, ... }:
{
  imports = [
    ./docker.nix
    ./virtualisation.nix
  ];

  options.spaceElevator.development.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      The development flavor: containers (Docker) and virtual machines
      (libvirt/QEMU with virt-manager). Sets the default for every
      option under spaceElevator.development.
    '';
  };
}
