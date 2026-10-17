#!/usr/bin/env bash
# Non-interactive test harness for the generator: produce a config for
# every desktop, GPU and flavor combination the wizard can reach, and
# assert the output is complete, correctly pinned, and switched on the
# way the answers said.
#
# This covers what the wizard *writes*. Whether those configurations
# evaluate is tests/checks.nix, run by `nix flake check`.
set -euo pipefail
cd "$(dirname "$0")/.."

export SE_NONINTERACTIVE=1
export SE_HOSTNAME=citest SE_USERNAME=ci SE_TIMEZONE=Etc/UTC
export SE_LOCALE=en_US.UTF-8 SE_KEYMAP=us

fail=0

# check <label> <description> <test...>
check() {
  local label="$1" description="$2"
  shift 2
  if ! "$@"; then
    echo "FAIL ($label): $description"
    fail=1
  fi
}

# Generate into a fresh directory and echo its path.
generate() {
  local out
  out=$(mktemp -d)/cfg
  SE_OUTDIR="$out" MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
  echo "$out"
}

has_line() { grep -qF -- "$2" "$1"; }

# The space-elevator input block starts above the first nixpkgs.url line.
input_before_nixpkgs() {
  local s n
  s=$(grep -n 'space-elevator = {' "$1" | head -1 | cut -d: -f1)
  n=$(grep -nE '^[[:space:]]*nixpkgs\.url' "$1" | head -1 | cut -d: -f1)
  [ -n "$s" ] && [ -n "$n" ] && [ "$s" -lt "$n" ]
}
lacks_line() { ! grep -qF -- "$2" "$1"; }

# An option set to true on its own line — not one of the commented-out
# suggestions, which are indented behind a "# ".
is_enabled() { grep -qE "^[[:space:]]+$2[[:space:]]*=[[:space:]]*true;" "$1"; }
is_not_enabled() { ! is_enabled "$1" "$2"; }

# Every .nix file under a directory parses. The redirect belongs to
# nix-instantiate, not to `check` — on `check` it swallows the FAIL
# line along with the output nobody wants.
parse_nix_under() {
  local f
  while read -r f; do
    check parse "$f does not parse as Nix" \
      bash -c 'nix-instantiate --parse "$1" >/dev/null' _ "$f"
  done < <(find "$1" -name '*.nix')
}

# ── Every desktop, with the optional flavors turned on ─────────────

for de in "KDE Plasma" "GNOME" "COSMIC" "Hyprland"; do
  case "$de" in
    "KDE Plasma") attr=plasma ;;
    GNOME) attr=gnome ;;
    COSMIC) attr=cosmic ;;
    Hyprland) attr=hyprland ;;
  esac

  out=$(SE_GPU=AMD SE_DE="$de" SE_FLAVORS="development,kdeconnect" generate)
  se="$out/hosts/citest/space-elevator.nix"
  host="$out/hosts/citest/citest.nix"

  for f in flake.nix flake/hosts.nix update.sh README.md \
    hosts/citest/citest.nix hosts/citest/configuration.nix \
    hosts/citest/space-elevator.nix hosts/citest/hardware-configuration.nix; do
    check "$de" "missing $f" test -f "$out/$f"
  done
  check "$de" "update.sh not executable" test -x "$out/update.sh"
  check "$de" "git repo not initialized" test -d "$out/.git"

  # The module set arrives as a flake input, not as a copy
  check "$de" "modules were vendored instead of taken from the input" test ! -e "$out/modules"
  check "$de" "space-elevator input missing" has_line "$out/flake.nix" "space-elevator = {"
  check "$de" "space-elevator input does not follow the stable branch" \
    has_line "$out/flake.nix" 'url = "github:jspadgett/space-elevator/stable";'
  check "$de" "space-elevator does not share nixpkgs" \
    has_line "$out/flake.nix" 'inputs.nixpkgs.follows = "nixpkgs";'

  # The host imports the module set and its switches, not a list of files
  check "$de" "host does not import the module set" \
    has_line "$host" "inputs.space-elevator.nixosModules.default"
  check "$de" "host does not import space-elevator.nix" has_line "$host" "./space-elevator.nix"
  check "$de" "host still imports a vendored copy" lacks_line "$host" "../../modules"

  # update.sh hands over to the newest release's updater
  check "$de" "update.sh does not run the packaged updater" \
    has_line "$out/update.sh" "github:jspadgett/space-elevator/stable#update"
  check "$de" "update.sh does not name its host" has_line "$out/update.sh" "--host citest"

  # Answers became options
  check "$de" "wrong nixpkgs pin" has_line "$out/flake.nix" "nixos-26.05"
  check "$de" "master switch missing" has_line "$se" "enable = true;"
  check "$de" "user not set" has_line "$se" 'user.name = "ci";'
  check "$de" "locale not set" has_line "$se" 'defaultLocale = "en_US.UTF-8";'
  check "$de" "keyboard layout not set" has_line "$se" 'keyboardLayout = "us";'
  check "$de" "desktop not enabled" has_line "$se" "desktop.$attr.enable = true;"
  check "$de" "GPU not enabled" has_line "$se" "gpu.amd.enable = true;"
  check "$de" "gaming not enabled" is_enabled "$se" 'gaming\.enable'
  check "$de" "development flavor missing" is_enabled "$se" 'development\.enable'
  check "$de" "theming not enabled" has_line "$se" "desktop.theming = {"
  check "$de" "theming input missing" has_line "$out/flake.nix" "catppuccin"
  check "$de" "theming module not imported by the host" \
    has_line "$host" "inputs.catppuccin.nixosModules.catppuccin"

  # Exactly one desktop is on; the others are offered as comments
  enabled=$(grep -cE '^\s+desktop\.(plasma|gnome|cosmic|hyprland)\.enable = true;' "$se")
  check "$de" "expected exactly one enabled desktop, found $enabled" test "$enabled" -eq 1
  offered=$(grep -cE '^\s+# desktop\.(plasma|gnome|cosmic|hyprland)\.enable = true;' "$se")
  check "$de" "expected the other three desktops as comments, found $offered" test "$offered" -eq 3

  # Nothing is left for the user to fill in by hand
  check "$de" "unsubstituted placeholder" \
    bash -c '! grep -rqE "@(USERNAME|LOCALE|KB_LAYOUT|HOSTNAME)@" "$1"' _ "$out"

  echo "OK: $de"
done

# ── No optional flavors: standard equipment is still standard ───────
# Gaming, theming and Firefox are not questions the wizard asks, so
# declining everything optional must still leave them on.

out=$(SE_GPU=AMD SE_DE=GNOME SE_FLAVORS="" generate)
se="$out/hosts/citest/space-elevator.nix"
check no-flavor "gaming is standard, should be on" is_enabled "$se" 'gaming\.enable'
check no-flavor "theming is standard, should be on" has_line "$se" "desktop.theming = {"
check no-flavor "theming input missing" has_line "$out/flake.nix" "catppuccin"
check no-flavor "theming module not imported by the host" \
  has_line "$out/hosts/citest/citest.nix" "inputs.catppuccin.nixosModules.catppuccin"
check no-flavor "Firefox not mentioned as standard" has_line "$se" "desktop.packages.firefox = false;"
check no-flavor "Big Picture session not offered" has_line "$se" "gaming.steam.gamescopeSession = true;"
check no-flavor "game streaming not offered" has_line "$se" "gaming.streaming.enable = true;"
check no-flavor "RGB control not offered" has_line "$se" "gaming.rgb.enable = true;"
check no-flavor "performance kernel not offered" has_line "$se" 'base.kernel = "zen";'
check no-flavor "development enabled without the flavor" is_not_enabled "$se" 'development\.enable'
check no-flavor "development not offered as a comment" has_line "$se" "# development.enable = true;"
check no-flavor "TLP not offered as a comment" has_line "$se" "# tuning.tlp.enable = true;"
check no-flavor "catppuccin not pinned to the release" \
  has_line "$out/flake.nix" "github:catppuccin/nix/release-26.05"
echo "OK: no-flavor config"

# ── Handheld: hhd on, TLP off even when asked for ────────────────────
# CI hardware never matches the DMI table, so this exercises the
# SE_HANDHELD override, which is the same path a script takes.

out=$(SE_GPU=AMD SE_DE="KDE Plasma" SE_FLAVORS="" SE_HANDHELD=1 SE_TLP=1 generate)
se="$out/hosts/citest/space-elevator.nix"
check handheld "handheld support not enabled" is_enabled "$se" 'gaming\.handheld\.enable'
check handheld "Big Picture session offered on top of handheld" lacks_line "$se" "gaming.steam.gamescopeSession"
check handheld "TLP enabled on a handheld" is_not_enabled "$se" 'tuning\.tlp\.enable'
check handheld "TLP not offered as a comment" has_line "$se" "# tuning.tlp.enable = true;"
check handheld "handheld comment missing" has_line "$se" "# Handheld gaming PC."
check handheld "handheld config still mentions autoLogin" lacks_line "$se" "autoLogin"
echo "OK: handheld config"

out=$(SE_GPU=AMD SE_DE="KDE Plasma" SE_FLAVORS="" SE_HANDHELD=0 SE_TLP=1 generate)
se="$out/hosts/citest/space-elevator.nix"
check laptop "TLP lost when handheld is declined" is_enabled "$se" 'tuning\.tlp\.enable'
check laptop "handheld support enabled on a laptop" is_not_enabled "$se" 'gaming\.handheld\.enable'
check laptop "Big Picture session no longer offered" has_line "$se" "#   gaming.steam.gamescopeSession = true;"
echo "OK: laptop config"

# ── KDE Connect: part of Plasma, a choice everywhere else ───────────

out=$(SE_GPU=AMD SE_DE=GNOME SE_FLAVORS="kdeconnect" generate)
check kdeconnect "not enabled when chosen on GNOME" \
  has_line "$out/hosts/citest/space-elevator.nix" "desktop.kdeconnect.enable = true;"

out=$(SE_GPU=AMD SE_DE="KDE Plasma" SE_FLAVORS="" generate)
check kdeconnect "Plasma should not re-enable what its flavor already includes" \
  is_not_enabled "$out/hosts/citest/space-elevator.nix" 'desktop\.kdeconnect\.enable'
echo "OK: kdeconnect"

# ── Every GPU answer ────────────────────────────────────────────────

for gpu in AMD:gpu.amd Intel:gpu.intel NVIDIA:gpu.nvidia; do
  vendor="${gpu%%:*}"
  attr="${gpu#*:}"
  out=$(SE_GPU="$vendor" SE_DE=GNOME SE_FLAVORS="" generate)
  check "gpu-$vendor" "driver not enabled" \
    grep -qE "^\s+$attr(\.enable = true;| = \{)" "$out/hosts/citest/space-elevator.nix"
done

out=$(SE_GPU="None / VM" SE_DE=GNOME SE_FLAVORS="" generate)
check gpu-none "a GPU driver was enabled for a VM" \
  bash -c '! grep -qE "^\s+gpu\." "$1"' _ "$out/hosts/citest/space-elevator.nix"
echo "OK: GPU variants"

# ── Upgrading an existing system ────────────────────────────────────
# Build a fixture in the OLD import-is-enable layout — the thing real
# users are upgrading from — and check the upgrade script reads it
# correctly and carries across what must not change.

old_style_config() {
  local root="$1" de="$2" gpu="$3"
  mkdir -p "$root/hosts/oldbox" "$root/modules/common" "$root/modules/desktop" "$root/modules/gpu"
  cat > "$root/flake.nix" <<'NIX'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  outputs = { ... }: { };
}
NIX
  cat > "$root/hosts/oldbox/oldbox.nix" <<NIX
{ inputs, ... }: {
  flake.nixosConfigurations.oldbox = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      ./configuration.nix
      ../../modules/common/base.nix
      ../../modules/common/base-locale.nix
      ../../modules/desktop/$de.nix
      ../../modules/gpu/$gpu.nix
      ../../modules/apps/docker.nix
      ../../modules/tuning/tlp.nix
      ../../modules/local/my-vpn.nix
    ];
  };
}
NIX
  cat > "$root/hosts/oldbox/configuration.nix" <<'NIX'
{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "oldbox";
  time.timeZone = "Europe/Berlin";
  users.users.dana = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$rounds=100000$abcdefgh$SOMEHASHVALUE";
  };
  environment.systemPackages = with pkgs; [ vim emacs ];
  system.stateVersion = "24.11";
}
NIX
  cat > "$root/hosts/oldbox/hardware-configuration.nix" <<'NIX'
{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/DEADBEEF";
  fileSystems."/" = { device = "/dev/mapper/cryptroot"; fsType = "btrfs"; options = [ "subvol=root" "compress=zstd" ]; };
}
NIX
  cat > "$root/modules/common/base-locale.nix" <<'NIX'
{ ... }:
{
  i18n.defaultLocale = "de_DE.UTF-8";
  services.xserver.xkb.layout = "de";
}
NIX
  mkdir -p "$root/modules/local"
  echo '{ ... }: { services.tailscale.enable = true; }' > "$root/modules/local/my-vpn.nix"
  : > "$root/modules/common/base.nix"
}

old=$(mktemp -d)/old
new=$(mktemp -d)/new
old_style_config "$old" plasma nvidia
SCAFFOLD_BIN="" bash upgrade.sh --config "$old" --output "$new" --yes --no-build >/dev/null

se="$new/hosts/oldbox/space-elevator.nix"
cfg="$new/hosts/oldbox/configuration.nix"
check upgrade "did not generate a config" test -f "$se"
check upgrade "stateVersion was not preserved" has_line "$cfg" 'system.stateVersion = "24.11";'
check upgrade "declared password was not carried over" has_line "$cfg" 'hashedPassword = "$6$rounds=100000$abcdefgh$SOMEHASHVALUE";'
check upgrade "hardware config was not carried over" has_line \
  "$new/hosts/oldbox/hardware-configuration.nix" 'cryptroot'
check upgrade "hand-edited filesystem options were lost" has_line \
  "$new/hosts/oldbox/hardware-configuration.nix" 'compress=zstd'
check upgrade "desktop was not detected" is_enabled "$se" 'desktop\.plasma\.enable'
check upgrade "GPU was not detected" grep -qE '^\s+gpu\.nvidia' "$se"
check upgrade "development flavor was not detected" is_enabled "$se" 'development\.enable'
check upgrade "TLP was not detected" is_enabled "$se" 'tuning\.tlp\.enable'
check upgrade "username was not detected" has_line "$se" 'user.name = "dana";'
check upgrade "timezone was not carried over" has_line "$cfg" 'time.timeZone = "Europe/Berlin";'
check upgrade "locale was not carried over" has_line "$se" 'defaultLocale = "de_DE.UTF-8";'
check upgrade "keyboard layout was not carried over" has_line "$se" 'keyboardLayout = "de";'
check upgrade "review notes missing" test -f "$new/UPGRADE-NOTES.md"
check upgrade "custom module not reported" has_line "$new/UPGRADE-NOTES.md" "local/my-vpn.nix"
check upgrade "review diff missing" test -f "$new/UPGRADE-REVIEW.diff"
check upgrade "old config was modified" has_line "$old/hosts/oldbox/configuration.nix" 'stateVersion = "24.11"'
check upgrade "regenerated host does not import the input" \
  has_line "$new/hosts/oldbox/oldbox.nix" "inputs.space-elevator.nixosModules.default"
check upgrade "a Space Elevator module was copied into the regenerated tree" \
  test ! -e "$new/modules/common"
echo "OK: upgrade from the old layout"

# The layout that shipped between the two: a settings.nix holding
# three spaceElevator options, with the modules still imported one by
# one. Different spellings — `locale` as a bare string,
# `keyboard.layout` — so the detection has to know all of them.
mid=$(mktemp -d)/mid
old_style_config "$mid" gnome intel-gpu
cat > "$mid/hosts/oldbox/settings.nix" <<'NIX'
{
  spaceElevator = {
    user.name = "dana";
    locale = "fr_FR.UTF-8";
    keyboard.layout = "fr";
  };
}
NIX
rm -f "$mid/modules/common/base-locale.nix"
mid2=$(mktemp -d)/mid2
SCAFFOLD_BIN="" bash upgrade.sh --config "$mid" --output "$mid2" --yes --no-build >/dev/null
ms="$mid2/hosts/oldbox/space-elevator.nix"
check upgrade-mid "username lost from settings.nix" has_line "$ms" 'user.name = "dana";'
check upgrade-mid "bare locale string not understood" has_line "$ms" 'defaultLocale = "fr_FR.UTF-8";'
check upgrade-mid "keyboard.layout not understood" has_line "$ms" 'keyboardLayout = "fr";'
check upgrade-mid "desktop lost" is_enabled "$ms" 'desktop\.gnome\.enable'
check upgrade-mid "GPU lost" is_enabled "$ms" 'gpu\.intel\.enable'
check upgrade-mid "stateVersion lost" \
  has_line "$mid2/hosts/oldbox/configuration.nix" 'system.stateVersion = "24.11";'
echo "OK: upgrade from the settings.nix layout"

# The same script has to handle a config it generated itself — this is
# how someone upgrades a second time.
gen=$(mktemp -d)/cfg
SE_GPU=Intel SE_DE=GNOME SE_FLAVORS="kdeconnect" SE_OUTDIR="$gen" MODULE_SOURCE="$PWD/modules" \
  bash scaffold.sh >/dev/null
again=$(mktemp -d)/again
SCAFFOLD_BIN="" bash upgrade.sh --config "$gen" --output "$again" --yes --no-build >/dev/null
re="$again/hosts/citest/space-elevator.nix"
check upgrade-again "desktop lost on re-upgrade" is_enabled "$re" 'desktop\.gnome\.enable'
check upgrade-again "GPU lost on re-upgrade" is_enabled "$re" 'gpu\.intel\.enable'
check upgrade-again "kdeconnect lost on re-upgrade" is_enabled "$re" 'desktop\.kdeconnect\.enable'
check upgrade-again "stateVersion lost on re-upgrade" \
  has_line "$again/hosts/citest/configuration.nix" 'system.stateVersion = "26.05";'
# The switches file lists every option you *didn't* pick as a comment.
# Reading those back as settings is the failure mode this guards.
check upgrade-again "a commented suggestion was read as a setting" \
  is_not_enabled "$re" 'desktop\.plasma\.enable'
check upgrade-again "a commented suggestion enabled the wrong GPU" \
  is_not_enabled "$re" 'gpu\.nvidia\.enable'
check upgrade-again "a commented suggestion enabled a flavor" \
  is_not_enabled "$re" 'development\.enable'
echo "OK: upgrade from the current layout"

# ── A hybrid laptop keeps its dGPU ──────────────────────────────────
# PRIME is the one answer the wizard writes as a block — `gpu.nvidia =
# { prime = { ... }; }` rather than a flat `enable = true;`. Detection
# has to read that form back. When it doesn't, the upgrade ships a
# config with no driver at all, and UPGRADE-REVIEW.diff only covers
# configuration.nix, so nothing says so.
#
# Bus IDs have to be detectable for the PRIME path to run at all, so
# the wizard and the upgrade both get a fake hybrid lspci.
fakebin=$(mktemp -d)
cat > "$fakebin/lspci" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"::0300"*) printf '00:02.0 "VGA compatible controller" "Intel Corporation" "UHD Graphics" -r04 "Dell" "Device 0c3d"\n01:00.0 "VGA compatible controller" "NVIDIA Corporation" "AD107M [GeForce RTX 4060 Mobile]" -ra1 "Dell" "Device 0c3d"\n' ;;
esac
EOF
chmod +x "$fakebin/lspci"

# Both scripts hand a directory they cannot write to sudo. The
# fixtures below belong to the test user, so opening the parent is all
# the privilege those calls need.
cat > "$fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-n" ] && shift
last=${*: -1}
case "$last" in /*) chmod u+wx "$(dirname "$last")" 2>/dev/null || true ;; esac
exec "$@"
EOF
chmod +x "$fakebin/sudo"

prime=$(mktemp -d)/prime
PATH="$fakebin:$PATH" SE_GPU=NVIDIA SE_PRIME=1 SE_DE="KDE Plasma" \
  SE_OUTDIR="$prime" MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
primed=$(mktemp -d)/primed
PATH="$fakebin:$PATH" SCAFFOLD_BIN="" \
  bash upgrade.sh --config "$prime" --output "$primed" --yes --no-build >/dev/null
pse="$primed/hosts/citest/space-elevator.nix"
check upgrade-prime "the NVIDIA driver was dropped" \
  grep -qE '^[[:space:]]+gpu\.nvidia[[:space:]]*=[[:space:]]*\{' "$pse"
check upgrade-prime "PRIME offload was dropped" \
  grep -qE '^[[:space:]]+prime[[:space:]]*=[[:space:]]*\{' "$pse"
check upgrade-prime "the iGPU bus ID was lost" has_line "$pse" 'intelBusId = "PCI:0:2:0";'
check upgrade-prime "the NVIDIA bus ID was lost" has_line "$pse" 'nvidiaBusId = "PCI:1:0:0";'
echo "OK: upgrade keeps PRIME offload"

# ── An old-layout hybrid laptop ─────────────────────────────────────
# The old layout keeps bus IDs inside the GPU module rather than in a
# switches file. Detection reads them from there and the regenerated
# config gets PRIME.
oldp=$(mktemp -d)/oldp
old_style_config "$oldp" plasma nvidia
cat > "$oldp/modules/gpu/nvidia.nix" <<'NIX'
{ ... }:
{
  hardware.nvidia.prime = {
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
}
NIX
oldpd=$(mktemp -d)/oldpd
PATH="$fakebin:$PATH" SCAFFOLD_BIN="" \
  bash upgrade.sh --config "$oldp" --output "$oldpd" --yes --no-build >/dev/null
opse="$oldpd/hosts/oldbox/space-elevator.nix"
check upgrade-prime-old "the NVIDIA driver was dropped" \
  grep -qE '^[[:space:]]+gpu\.nvidia[[:space:]]*=[[:space:]]*\{' "$opse"
check upgrade-prime-old "PRIME offload was dropped" \
  grep -qE '^[[:space:]]+prime[[:space:]]*=[[:space:]]*\{' "$opse"
check upgrade-prime-old "the NVIDIA bus ID was lost" has_line "$opse" 'nvidiaBusId = "PCI:1:0:0";'
echo "OK: old-layout PRIME offload survives"

# ── Bus IDs imply the driver ────────────────────────────────────────
# Offload bus IDs in the host config with no GPU module imported.
# Detection finds no GPU; the bus IDs name an NVIDIA card, so the
# regenerated config gets the driver.
guard=$(mktemp -d)/guard
old_style_config "$guard" plasma nvidia
sed -i '/modules\/gpu\/nvidia\.nix/d' "$guard/hosts/oldbox/oldbox.nix"
sed -i 's|  system.stateVersion = "24.11";|  hardware.nvidia.prime = {\n    intelBusId = "PCI:0:2:0";\n    nvidiaBusId = "PCI:1:0:0";\n  };\n  system.stateVersion = "24.11";|' \
  "$guard/hosts/oldbox/configuration.nix"
check upgrade-prime-guard "fixture still imports a GPU module" \
  lacks_line "$guard/hosts/oldbox/oldbox.nix" "modules/gpu/nvidia.nix"
guarded=$(mktemp -d)/guarded
PATH="$fakebin:$PATH" SCAFFOLD_BIN="" \
  bash upgrade.sh --config "$guard" --output "$guarded" --yes --no-build >/dev/null
gse="$guarded/hosts/oldbox/space-elevator.nix"
check upgrade-prime-guard "bus IDs were present but the driver was dropped" \
  grep -qE '^[[:space:]]+gpu\.nvidia[[:space:]]*=[[:space:]]*\{' "$gse"
check upgrade-prime-guard "the NVIDIA bus ID was lost" has_line "$gse" 'nvidiaBusId = "PCI:1:0:0";'
echo "OK: PRIME bus IDs imply the NVIDIA driver"

# ── The current layout carries the tree across ──────────────────────
# Everything in the old tree reaches the output untouched. The copy of
# the modules a config carried before Space Elevator was a flake input
# is replaced by the input.
#
# A config as the wizard wrote it before then: the module set copied
# into modules/, imported as ../../modules, and no space-elevator input.
vendored_config() {
  local root="$1"
  cp -R modules "$root/modules"
  chmod -R u+w "$root/modules"
  sed -i -E 's|^([[:space:]]*)inputs\.space-elevator\.nixosModules\.default$|\1../../modules|' \
    "$root/hosts/citest/citest.nix"
  awk '/^    # The modules\. The stable branch/ { skip = 1 }
       skip && /^    nixpkgs\.url/ { skip = 0 }
       !skip { print }' "$root/flake.nix" > "$root/flake.nix.tmp"
  mv "$root/flake.nix.tmp" "$root/flake.nix"
  printf '#!/usr/bin/env bash\nnix flake update\n' > "$root/update.sh"
}

cur=$(mktemp -d)/cur
SE_GPU=NVIDIA SE_DE="KDE Plasma" SE_TLP=1 SE_OUTDIR="$cur" \
  MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
vendored_config "$cur"
check vendored-fixture "fixture still has the input" lacks_line "$cur/flake.nix" "space-elevator = {"
check vendored-fixture "fixture does not import its copy" has_line "$cur/hosts/citest/citest.nix" "../../modules"
curse="$cur/hosts/citest/space-elevator.nix"

# Six switches the wizard never reads back, set the way a user would.
sed -i 's/    gaming.enable = true;/    gaming.enable = false;/' "$curse"
sed -i 's/      flavor = "mocha";/      flavor = "latte";/' "$curse"
sed -i 's/      accent = "mauve";/      accent = "teal";/' "$curse"
sed -i 's|    user.name = "ci";|    user.name = "ci";\n    base.kernel = "zen";\n    network.firewall.allowedTCPPorts = [ 8080 ];|' "$curse"
sed -i 's|    gpu.nvidia.enable = true;|    gpu.nvidia = {\n      enable = true;\n      driver = "legacy_580";\n    };|' "$curse"
sed -i 's|    tuning.tlp.enable = true;|    tuning.tlp = {\n      enable = true;\n      chargeThresholds = null;\n    };|' "$curse"

# Things of the user's that live outside the host directory.
mkdir -p "$cur/modules/local"
printf '{ ... }: { services.tailscale.enable = true; }\n' > "$cur/modules/local/my-vpn.nix"
printf '{"nodes":{"root":{}},"root":"root","version":7}\n' > "$cur/flake.lock"
printf '\n# my own flake comment\n' >> "$cur/flake.nix"
printf '\n# my own wiring comment\n' >> "$cur/hosts/citest/citest.nix"

# Markers in the files Space Elevator owns; each has to be replaced.
printf '\n# stale module marker\n' >> "$cur/modules/gpu/nvidia.nix"
printf '\n# stale default marker\n' >> "$cur/modules/default.nix"
printf '\n# stale readme marker\n' >> "$cur/README.md"
printf '\n# stale update marker\n' >> "$cur/update.sh"

git -C "$cur" init -q
git -C "$cur" add -A
git -C "$cur" -c user.email=ci@test -c user.name=ci commit -qm "user history"
curhead=$(git -C "$cur" rev-parse HEAD)
cp "$curse" "$cur.se-before"
cp "$cur/hosts/citest/configuration.nix" "$cur.cfg-before"

curup=$(mktemp -d)/curup
SCAFFOLD_BIN="" bash upgrade.sh --config "$cur" --output "$curup" --yes --no-build >/dev/null

check upgrade-preserve "space-elevator.nix was not carried byte for byte" \
  cmp -s "$cur.se-before" "$curup/hosts/citest/space-elevator.nix"
check upgrade-preserve "configuration.nix was not carried byte for byte" \
  cmp -s "$cur.cfg-before" "$curup/hosts/citest/configuration.nix"
check upgrade-preserve "flake.nix was not carried" \
  has_line "$curup/flake.nix" "# my own flake comment"
check upgrade-preserve "the host wiring file was not carried" \
  has_line "$curup/hosts/citest/citest.nix" "# my own wiring comment"
check upgrade-preserve "flake.lock was not carried" \
  cmp -s "$cur/flake.lock" "$curup/flake.lock"
check upgrade-preserve "a module directory outside the set was dropped" \
  cmp -s "$cur/modules/local/my-vpn.nix" "$curup/modules/local/my-vpn.nix"
check upgrade-preserve "git history was not carried" test -d "$curup/.git"
check upgrade-preserve "git history is not the user's" \
  bash -c 'test "$(git -C "$1" rev-parse HEAD 2>/dev/null)" = "$2"' _ "$curup" "$curhead"
check upgrade-preserve "the vendored copy of a module was kept" \
  test ! -e "$curup/modules/gpu"
check upgrade-preserve "the vendored modules/default.nix was kept" \
  test ! -e "$curup/modules/default.nix"
check upgrade-preserve "flake.nix did not gain the space-elevator input" \
  has_line "$curup/flake.nix" 'url = "github:jspadgett/space-elevator/stable";'
check upgrade-preserve "the input was added more than once" \
  test "$(grep -c 'space-elevator = {' "$curup/flake.nix")" -eq 1
check upgrade-preserve "the input is not inside the inputs block, ahead of nixpkgs" \
  input_before_nixpkgs "$curup/flake.nix"
check upgrade-preserve "the host still imports the vendored copy" \
  lacks_line "$curup/hosts/citest/citest.nix" "../../modules"
check upgrade-preserve "the host does not import the input" \
  has_line "$curup/hosts/citest/citest.nix" "inputs.space-elevator.nixosModules.default"
check upgrade-preserve "the migrated flake.nix does not parse" \
  bash -c '! command -v nix-instantiate >/dev/null || nix-instantiate --parse "$1" >/dev/null' _ "$curup/flake.nix"
check upgrade-preserve "README.md was not replaced" \
  lacks_line "$curup/README.md" "# stale readme marker"
check upgrade-preserve "update.sh was not replaced" \
  lacks_line "$curup/update.sh" "# stale update marker"
echo "OK: the current layout carries the tree across"

# The diff is the only place a template change shows up now, so it has
# to cover every file that carried over unchanged, plus the module set.
curdiff="$curup/UPGRADE-REVIEW.diff"
check upgrade-preserve-diff "diff does not cover space-elevator.nix" \
  has_line "$curdiff" "space-elevator.nix"
check upgrade-preserve-diff "diff does not cover configuration.nix" \
  has_line "$curdiff" "configuration.nix"
check upgrade-preserve-diff "diff does not cover the host wiring file" \
  has_line "$curdiff" "citest.nix"
check upgrade-preserve-diff "diff does not cover the module set" \
  has_line "$curdiff" "-# stale module marker"
echo "OK: the review diff covers what was kept"

# The notes are where anything not carried has to be named.
curnotes="$curup/UPGRADE-NOTES.md"
check upgrade-preserve-notes "notes do not say the tree carried over unchanged" \
  has_line "$curnotes" "Carried across unchanged"
check upgrade-preserve-notes "notes do not mention flake.lock" \
  has_line "$curnotes" "flake.lock"
check upgrade-preserve-notes "notes do not explain the move to the input" \
  has_line "$curnotes" "Space Elevator is now a flake input"
echo "OK: the notes describe what carried over"

# Upgrading a config that already takes the input changes nothing about
# how it gets its modules: no copy appears, and the input isn't doubled.
inp=$(mktemp -d)/inp
SE_GPU=AMD SE_DE=GNOME SE_OUTDIR="$inp" MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
inpup=$(mktemp -d)/inpup
SCAFFOLD_BIN="" bash upgrade.sh --config "$inp" --output "$inpup" --yes --no-build >/dev/null
check upgrade-input "a copy of the modules appeared" test ! -e "$inpup/modules"
check upgrade-input "flake.nix changed" cmp -s "$inp/flake.nix" "$inpup/flake.nix"
check upgrade-input "the host file changed" \
  cmp -s "$inp/hosts/citest/citest.nix" "$inpup/hosts/citest/citest.nix"
echo "OK: an input-layout config upgrades in place"

# A current-layout host keeps its own stateVersion, so a config the
# wizard cannot read one from is still upgradable.
nosv=$(mktemp -d)/nosv
SE_GPU=Intel SE_DE=GNOME SE_OUTDIR="$nosv" MODULE_SOURCE="$PWD/modules" \
  bash scaffold.sh >/dev/null
sed -i '/system\.stateVersion/d' "$nosv/hosts/citest/configuration.nix"
nosvup=$(mktemp -d)/nosvup
check upgrade-preserve-nosv "a missing stateVersion stopped the upgrade" \
  bash -c 'SCAFFOLD_BIN="" bash upgrade.sh --config "$1" --output "$2" --yes --no-build >/dev/null' \
  _ "$nosv" "$nosvup"
echo "OK: the current layout does not need a detected stateVersion"

# ── The default output directory ────────────────────────────────────
# With no --output the new tree is written beside the config, so on a
# real /etc/nixos the upgrade creates /etc/nixos.new — a directory it
# has no permission to create, since it runs unprivileged. The fixture
# stages that with a mode root would ignore, so it only means
# something as a normal user.
if [ "$(id -u)" -ne 0 ]; then
  etc=$(mktemp -d)/etc
  mkdir -p "$etc"
  SE_GPU=Intel SE_DE=GNOME SE_OUTDIR="$etc/nixos" MODULE_SOURCE="$PWD/modules" \
    bash scaffold.sh >/dev/null
  chmod 555 "$etc"
  PATH="$fakebin:$PATH" SCAFFOLD_BIN="" \
    bash upgrade.sh --config "$etc/nixos" --yes --no-build >/dev/null 2>&1 || true
  check upgrade-default-output "the tree was not written beside the config" \
    test -f "$etc/nixos.new/hosts/citest/space-elevator.nix"
  check upgrade-default-output "the switches file did not carry across" \
    has_line "$etc/nixos.new/hosts/citest/space-elevator.nix" 'user.name = "ci";'
  check upgrade-default-output "the new tree does not belong to this user" \
    test -w "$etc/nixos.new"
  chmod 755 "$etc"
  echo "OK: the default output directory is created"
else
  echo "SKIP: running as root, an unwritable directory cannot be staged"
fi

# ── An output directory that is already there ───────────────────────
# /mnt/etc/nixos exists and belongs to root whenever the partitioning
# was done by hand, and after any earlier run. mkdir -p is happy with
# a directory that already exists, so the wizard has to decide on
# writability. Staged with a mode, which root ignores.
if [ "$(id -u)" -ne 0 ]; then
  taken=$(mktemp -d)/nixos
  mkdir -p "$taken"
  chmod 555 "$taken"
  PATH="$fakebin:$PATH" SE_GPU=Intel SE_DE=GNOME SE_OUTDIR="$taken" \
    MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null 2>&1 || true
  check outdir-taken "nothing was generated into an unwritable directory" \
    test -f "$taken/flake.nix"
  check outdir-taken "the generated tree does not belong to this user" \
    test -w "$taken"
  chmod -R u+w "$taken" 2>/dev/null || true
  echo "OK: an unwritable output directory is taken over"

  # Taking the directory itself over says nothing about what is inside
  # it. Rather than rewrite a tree it was not given, the wizard stops
  # and names the command that hands the whole thing across.
  deep=$(mktemp -d)/nixos
  mkdir -p "$deep/hosts"
  chmod 555 "$deep/hosts"
  deepmsg=$(PATH="$fakebin:$PATH" SE_GPU=Intel SE_DE=GNOME SE_OUTDIR="$deep" \
    MODULE_SOURCE="$PWD/modules" bash scaffold.sh 2>&1 || true)
  check outdir-inside "an unwritable subdirectory was not reported" \
    bash -c 'grep -qF "$1" <<<"$2"' _ "$deep/hosts" "$deepmsg"
  check outdir-inside "the message does not name the command to run" \
    bash -c 'grep -qF "chown -R" <<<"$1"' _ "$deepmsg"
  chmod -R u+w "$deep" 2>/dev/null || true
  echo "OK: an unwritable subdirectory stops the run with instructions"
else
  echo "SKIP: running as root, an unwritable directory cannot be staged"
fi

# Regenerated trees resolve their inputs fresh, so an old lock must
# not travel with them.
oldlock=$(mktemp -d)/oldlock
old_style_config "$oldlock" gnome amdgpu
printf '{"nodes":{"root":{}},"root":"root","version":7}\n' > "$oldlock/flake.lock"
oldlockup=$(mktemp -d)/oldlockup
SCAFFOLD_BIN="" bash upgrade.sh --config "$oldlock" --output "$oldlockup" --yes --no-build >/dev/null
check upgrade-old-lock "an old lock was carried into a regenerated tree" \
  test ! -f "$oldlockup/flake.lock"
echo "OK: regenerated trees get a fresh lock"

# Hosts other than the one being upgraded ride along with the tree.
# The non-interactive path picks the host matching this machine, so
# the fixture names one after it.
me=$(hostname)
if [ -n "$me" ] && [ "$me" = "${me##*/}" ]; then
  multi=$(mktemp -d)/multi
  SE_HOSTNAME="$me" SE_GPU=Intel SE_DE=GNOME SE_OUTDIR="$multi" \
    MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
  mkdir -p "$multi/hosts/spare"
  printf '{ ... }: { networking.hostName = "spare"; }\n' > "$multi/hosts/spare/configuration.nix"
  multiup=$(mktemp -d)/multiup
  SCAFFOLD_BIN="" bash upgrade.sh --config "$multi" --output "$multiup" --yes --no-build >/dev/null
  check upgrade-preserve-hosts "another host was dropped" \
    cmp -s "$multi/hosts/spare/configuration.nix" "$multiup/hosts/spare/configuration.nix"
  echo "OK: other hosts ride along"
else
  echo "SKIP: hostname unusable as a host directory name"
fi

# Same trap, from the other direction: a machine with no GPU module
# and no flavors must come back with no GPU module and no flavors.
bare=$(mktemp -d)/bare
SE_GPU="None / VM" SE_DE=Hyprland SE_FLAVORS="" SE_OUTDIR="$bare" MODULE_SOURCE="$PWD/modules" \
  bash scaffold.sh >/dev/null
bare2=$(mktemp -d)/bare2
SCAFFOLD_BIN="" bash upgrade.sh --config "$bare" --output "$bare2" --yes --no-build >/dev/null
rb="$bare2/hosts/citest/space-elevator.nix"
check upgrade-bare "desktop lost" is_enabled "$rb" 'desktop\.hyprland\.enable'
check upgrade-bare "invented a GPU driver" bash -c '! grep -qE "^\s+gpu\." "$1"' _ "$rb"
check upgrade-bare "invented a flavor" is_not_enabled "$rb" 'development\.enable'
check upgrade-bare "invented KDE Connect" is_not_enabled "$rb" 'desktop\.kdeconnect\.enable'
echo "OK: upgrade invents nothing"

# ── The updater ─────────────────────────────────────────────────────
# A config wired like a generated one, with every input a local git
# repository standing in for GitHub: a Space Elevator whose stable
# branch moves, and nixpkgs and catppuccin with one branch per NixOS
# release. nixos-rebuild is faked, so this checks what the updater
# does to the config — the lock, the release lines, the commit, the
# way back — not a real build.

if command -v nix >/dev/null 2>&1; then
  upd=$(mktemp -d)
  export GIT_AUTHOR_NAME=ci GIT_AUTHOR_EMAIL=ci@test GIT_COMMITTER_NAME=ci GIT_COMMITTER_EMAIL=ci@test

  # fake_repo <dir> <branch> — a git repo holding a flake with no outputs
  fake_repo() {
    mkdir -p "$1"
    git -C "$1" init -q -b "$2"
    printf '{ outputs = _: { }; }\n' > "$1/flake.nix"
    git -C "$1" add -A
    git -C "$1" commit -qm init
  }
  fake_repo "$upd/nixpkgs" nixos-26.05
  git -C "$upd/nixpkgs" branch -q nixos-26.11
  fake_repo "$upd/catppuccin" release-26.05
  git -C "$upd/catppuccin" branch -q release-26.11

  # se_release <version> <nixosRelease> — a new release on stable
  se_release() {
    printf '{ version = "%s"; nixosRelease = "%s"; }\n' "$1" "$2" > "$upd/se/release.nix"
    git -C "$upd/se" add -A
    git -C "$upd/se" commit -qm "v$1"
  }
  mkdir -p "$upd/se"
  git -C "$upd/se" init -q -b stable
  cat > "$upd/se/flake.nix" <<'NIX'
{
  inputs.nixpkgs.url = "path:/dev/null";
  outputs = _: { nixosModules.default = { }; };
}
NIX
  se_release 1.2.0 26.05

  cfg="$upd/cfg"
  mkdir -p "$cfg/hosts/citest"
  cat > "$cfg/flake.nix" <<NIX
{
  inputs = {
    space-elevator = {
      url = "git+file://$upd/se?ref=stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "git+file://$upd/nixpkgs?ref=nixos-26.05";
    catppuccin.url = "git+file://$upd/catppuccin?ref=release-26.05";
  };
  outputs = _: { };
}
NIX
  git -C "$cfg" init -q
  git -C "$cfg" add -A
  git -C "$cfg" commit -qm "generated"

  # nixos-rebuild that records what it was asked and fails on request;
  # sudo that just runs the command.
  updbin=$(mktemp -d)
  cat > "$updbin/nixos-rebuild" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_REBUILD_LOG:?}"
[ "${FAKE_REBUILD_FAIL:-0}" = 1 ] && exit 1
[ "$1" = build ] && ln -sfn "$(mktemp -d)" result
exit 0
EOF
  printf '#!/usr/bin/env bash\nexec "$@"\n' > "$updbin/sudo"
  chmod +x "$updbin/nixos-rebuild" "$updbin/sudo"
  export FAKE_REBUILD_LOG="$upd/rebuild.log"
  : > "$FAKE_REBUILD_LOG"

  run_update() { PATH="$updbin:$PATH" bash update.sh --config "$cfg" "$@"; }
  locked_rev() {  # locked_rev <input> — full revision in the config's lock
    nix --extra-experimental-features "nix-command flakes" eval --impure --raw --expr \
      "(builtins.fromJSON (builtins.readFile $cfg/flake.lock)).nodes.\"$1\".locked.rev"
  }
  quiet() { "$@" >/dev/null 2>&1; }

  # First run: no lock yet. One is made, built against, kept.
  check update-first "the first update failed" quiet run_update --yes --no-switch
  check update-first "no lock was written" test -f "$cfg/flake.lock"
  check update-first "Space Elevator is not locked to stable's head" \
    test "$(locked_rev space-elevator 2>/dev/null)" = "$(git -C "$upd/se" rev-parse HEAD)"
  check update-first "nothing was built" grep -q "^build --flake $cfg#citest" "$FAKE_REBUILD_LOG"
  check update-first "--no-switch switched" bash -c '! grep -q "^switch" "$1"' _ "$FAKE_REBUILD_LOG"
  git -C "$cfg" add -A
  git -C "$cfg" commit -qm "locked"

  # --check with nothing new, then with a release out: it reports and
  # touches nothing.
  out_check=$(run_update --check 2>&1 || true)
  check update-check "an up-to-date config was not reported as such" \
    bash -c 'grep -q "1.2.0 is the newest" <<<"$1"' _ "$out_check"
  se_release 1.2.1 26.05
  cp "$cfg/flake.lock" "$upd/lock.before-check"
  out_check=$(run_update --check 2>&1 || true)
  check update-check "a new release was not reported" \
    bash -c 'grep -q "1.2.1 is out" <<<"$1"' _ "$out_check"
  check update-check "--check changed the lock" cmp -s "$upd/lock.before-check" "$cfg/flake.lock"

  # A failed build puts flake.nix and flake.lock back exactly.
  cp "$cfg/flake.nix" "$upd/flake.before-fail"
  cp "$cfg/flake.lock" "$upd/lock.before-fail"
  check update-fail "a failed build was reported as success" \
    bash -c '! FAKE_REBUILD_FAIL=1 "$@" >/dev/null 2>&1' _ run_update --yes
  check update-fail "flake.lock was not restored after a failed build" \
    cmp -s "$upd/lock.before-fail" "$cfg/flake.lock"
  check update-fail "flake.nix was not restored after a failed build" \
    cmp -s "$upd/flake.before-fail" "$cfg/flake.nix"

  # A release that moves to the next NixOS. Asked without --yes, the
  # answer is no (there is no terminal), and nothing may change.
  se_release 1.3.0 26.11
  check update-decline "declining the release move failed the run" quiet run_update
  check update-decline "the lock changed although the move was declined" \
    cmp -s "$upd/lock.before-fail" "$cfg/flake.lock"
  check update-decline "flake.nix changed although the move was declined" \
    has_line "$cfg/flake.nix" "ref=nixos-26.05"

  # Accepted: Space Elevator, nixpkgs and catppuccin all move, the
  # system is switched, and the update is one commit.
  : > "$FAKE_REBUILD_LOG"
  check update-release "the release update failed" quiet run_update --yes
  check update-release "nixpkgs was not moved to the new release" \
    has_line "$cfg/flake.nix" "ref=nixos-26.11"
  check update-release "catppuccin was not moved to the new release" \
    has_line "$cfg/flake.nix" "ref=release-26.11"
  check update-release "the old release is still named" lacks_line "$cfg/flake.nix" "26.05"
  check update-release "Space Elevator is not locked to the new release" \
    test "$(locked_rev space-elevator 2>/dev/null)" = "$(git -C "$upd/se" rev-parse HEAD)"
  check update-release "nixpkgs is not locked to the new release branch" \
    test "$(locked_rev nixpkgs 2>/dev/null)" = "$(git -C "$upd/nixpkgs" rev-parse nixos-26.11)"
  check update-release "the system was not switched" grep -q "^switch --flake $cfg#citest" "$FAKE_REBUILD_LOG"
  check update-release "the update was not committed" \
    bash -c 'git -C "$1" log -1 --format=%s | grep -q "1.2.0 → 1.3.0, NixOS 26.05 → 26.11"' _ "$cfg"
  check update-release "the commit left changes behind" \
    bash -c 'git -C "$1" diff --quiet HEAD -- flake.nix flake.lock' _ "$cfg"

  # A config that still carries its own copy is pointed at the upgrade.
  vend=$(mktemp -d)/vend
  SE_GPU=AMD SE_DE=GNOME SE_OUTDIR="$vend" MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
  vendored_config "$vend"
  vendmsg=$(PATH="$updbin:$PATH" bash update.sh --config "$vend" --yes 2>&1 || true)
  check update-vendored "a vendored config was not sent to the upgrade" \
    bash -c 'grep -q "space-elevator/stable#upgrade" <<<"$1"' _ "$vendmsg"
  echo "OK: the updater"
else
  echo "SKIP: nix not available, skipping the updater"
fi

# ── The generated file is valid Nix ─────────────────────────────────
# (Evaluating the whole config needs nixpkgs; parsing does not.)

if command -v nix-instantiate >/dev/null 2>&1; then
  out=$(SE_GPU=NVIDIA SE_DE="KDE Plasma" SE_FLAVORS="development" generate)
  parse_nix_under "$out"
  echo "OK: generated Nix parses"

  # The parse check has to name the file it failed on. Nix prints its
  # own error to stderr either way; what is at stake is the FAIL line
  # that says which check failed and on what.
  broken=$(mktemp -d)
  printf '{ = ;\n' > "$broken/broken.nix"
  brokenout=$( (parse_nix_under "$broken") 2>/dev/null || true )
  check harness "a file that does not parse was counted but never named" \
    bash -c 'grep -q "FAIL (parse)" <<<"$1"' _ "$brokenout"
  echo "OK: a failing parse says so"
else
  echo "SKIP: nix-instantiate not available, skipping parse check"
fi

exit $fail
