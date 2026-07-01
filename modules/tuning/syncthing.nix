# modules/features/syncthing.nix
# Syncthing file synchronization running as your user.
# The scaffold substitutes your username; web UI at http://127.0.0.1:8384
{ ... }:
{
  services.syncthing = {
    enable = true;
    user = "@USERNAME@";
    dataDir = "/home/@USERNAME@";
    openDefaultPorts = true;
  };
}
