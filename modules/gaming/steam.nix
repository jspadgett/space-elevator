# modules/gaming/steam.nix
# Steam with Remote Play, local game transfers, gamescope, GE-Proton,
# and Xbox Bluetooth controller support.
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    # GE-Proton preinstalled: pick it per-game under
    # Properties -> Compatibility for titles that need it
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  programs.gamescope = {
    enable = true;
    # capSysNice grants gamescope realtime scheduling, but on NixOS it
    # is known to prevent games launching from *within* Steam
    # (pressure-vessel can't inherit the capability). Keep it off.
    capSysNice = false;
  };

  # Xbox controllers over Bluetooth (wired pads and Steam controllers
  # are handled by steam-hardware, enabled by programs.steam)
  hardware.xpadneo.enable = true;
}
