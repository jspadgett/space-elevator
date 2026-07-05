# iso/iso.nix — the Space Elevator installer ISO.
# Build: nix build .#nixosConfigurations.space-elevator-iso.config.system.build.isoImage
# The image lands in result/iso/.
{ lib, pkgs, modulesPath, space-elevator, ... }:
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  # ── Branding ──────────────────────────────────────────────────────
  isoImage.isoBaseName = "space-elevator";
  isoImage.volumeID = "SPACE_ELEVATOR";
  # zstd builds much faster than the default xz at a modest size cost;
  # the minimal base leaves plenty of headroom under GitHub's 2 GiB
  # release-asset limit.
  isoImage.squashfsCompression = "zstd -Xcompression-level 19";

  # ── The wizard, preinstalled and offline-capable ──────────────────
  # space-elevator carries its own modules and runtime tools in its
  # closure, so the wizard works before the network is even up.
  environment.systemPackages = [
    space-elevator
    pkgs.git      # generated configs are git repos
    pkgs.parted   # partitioning per the install guide
    pkgs.gptfdisk
  ];

  # Flakes on by default: the wizard, nixos-install --flake, and the
  # generated config all work with no --experimental-features flags.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.download-attempts = 5; # be stubborn about flaky networks

  # ── Friendly networking ───────────────────────────────────────────
  # NetworkManager (nmtui is a menu) instead of the minimal ISO's
  # default wpa_supplicant (which is config files).
  networking.networkmanager.enable = true;
  networking.wireless.enable = false;

  # ── Greeting on the auto-logged-in console ────────────────────────
  services.getty.helpLine = lib.mkAfter ''

    <<< Space Elevator installer — the wizard starts automatically >>>
    Type 'space-elevator' to relaunch it at any time.
  '';

  # The wizard owns the whole journey (Wi-Fi, disks, install), so it
  # starts automatically on the main console. Quitting it drops to a
  # normal shell; type space-elevator to start again.
  programs.bash.interactiveShellInit = ''
    if [ "$(tty 2>/dev/null)" = "/dev/tty1" ] && [ -z "''${SPACE_ELEVATOR_GREETED:-}" ]; then
      export SPACE_ELEVATOR_GREETED=1
      space-elevator || true
      echo
      echo "  Type 'space-elevator' to relaunch the installer."
      echo "  Manual tools: nmtui (Wi-Fi), parted, nixos-install."
      echo
    fi
  '';

  system.stateVersion = "26.05";
}
