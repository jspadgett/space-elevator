# modules/development/virtualisation.nix
# Full virtualization: libvirt/QEMU + virt-manager
{ config, lib, ... }:
let
  cfg = config.spaceElevator.development.virtualisation;
  user = config.spaceElevator.user;
in
{
  options.spaceElevator.development.virtualisation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.development.enable;
      defaultText = lib.literalExpression "config.spaceElevator.development.enable";
      description = "libvirt/QEMU with the virt-manager GUI.";
    };

    addUserToGroup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Put spaceElevator.user in the "libvirtd" group, so virt-manager
        can talk to the system daemon without a password prompt every
        time. No effect when spaceElevator.user is unset.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;

    users.users = lib.mkIf (cfg.addUserToGroup && user != null) {
      ${user}.extraGroups = [ "libvirtd" ];
    };
  };
}
