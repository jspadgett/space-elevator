# modules/features/appimage.nix
# Run AppImages directly via binfmt
{ ... }:
{
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
