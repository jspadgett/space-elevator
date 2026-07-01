# modules/features/virtualisation.nix
# Full virtualization: libvirt/QEMU + virt-manager
{ ... }:
{
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
}
