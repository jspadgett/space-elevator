# modules/features/flatpak.nix
# Flatpak with Flathub remote added on activation
{ ... }:
{
  services.flatpak.enable = true;
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ ];
    script = ''
      /run/current-system/sw/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    '';
  };
}
