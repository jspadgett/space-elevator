# modules/desktop/desktop-packages.nix
# Everyday desktop applications plus the file/disk/system plumbing a
# mainstream distro ships by default.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Everyday apps
    kitty
    mpv
    imv
    libreoffice
    file-roller
    pavucontrol

    # Archive backends (file-roller and friends shell out to these)
    zip
    unzip
    p7zip
    unrar

    # Disk formatting & partitioning (udisks2/file managers need the
    # mkfs backends to format removable drives)
    gparted
    dosfstools   # FAT32
    exfatprogs   # exFAT
    ntfs3g       # NTFS
    smartmontools # disk health (smartctl)

    # File & system diagnosis
    file
    tree
    ncdu
    btop
    usbutils     # lsusb
    pciutils     # lspci
  ];
}
