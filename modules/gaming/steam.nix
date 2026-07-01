# modules/features/steam.nix
# Steam with Remote Play and gamescope
{ ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };
}
