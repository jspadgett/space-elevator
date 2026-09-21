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
lacks_line() { ! grep -qF -- "$2" "$1"; }

# An option set to true on its own line — not one of the commented-out
# suggestions, which are indented behind a "# ".
is_enabled() { grep -qE "^[[:space:]]+$2[[:space:]]*=[[:space:]]*true;" "$1"; }
is_not_enabled() { ! is_enabled "$1" "$2"; }

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

  # The complete module set is vendored, byte for byte
  check "$de" "vendored modules differ from source" diff -r modules "$out/modules"

  # The host imports the module set and its switches, not a list of files
  check "$de" "host does not import the module set" has_line "$host" "../../modules"
  check "$de" "host does not import space-elevator.nix" has_line "$host" "./space-elevator.nix"
  check "$de" "host still imports individual modules" \
    lacks_line "$host" "../../modules/"

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
# The modules are all vendored even when unused — that is the point
check no-flavor "development module not vendored" test -f "$out/modules/development/docker.nix"
check no-flavor "TLP module not vendored" test -f "$out/modules/tuning/tlp.nix"
echo "OK: no-flavor config"

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
# Everything in the old tree reaches the output untouched. Only the
# directories Space Elevator ships are replaced.
cur=$(mktemp -d)/cur
SE_GPU=NVIDIA SE_DE="KDE Plasma" SE_TLP=1 SE_OUTDIR="$cur" \
  MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
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
check upgrade-preserve "a Space Elevator module was not replaced" \
  lacks_line "$curup/modules/gpu/nvidia.nix" "# stale module marker"
check upgrade-preserve "modules/default.nix was not replaced" \
  lacks_line "$curup/modules/default.nix" "# stale default marker"
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
echo "OK: the notes describe what carried over"

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
  mkdir -p "$deep/modules"
  chmod 555 "$deep/modules"
  deepmsg=$(PATH="$fakebin:$PATH" SE_GPU=Intel SE_DE=GNOME SE_OUTDIR="$deep" \
    MODULE_SOURCE="$PWD/modules" bash scaffold.sh 2>&1 || true)
  check outdir-inside "an unwritable subdirectory was not reported" \
    bash -c 'grep -qF "$1" <<<"$2"' _ "$deep/modules" "$deepmsg"
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

# ── The generated file is valid Nix ─────────────────────────────────
# (Evaluating the whole config needs nixpkgs; parsing does not.)

if command -v nix-instantiate >/dev/null 2>&1; then
  out=$(SE_GPU=NVIDIA SE_DE="KDE Plasma" SE_FLAVORS="development" generate)
  while read -r f; do
    check parse "$f does not parse as Nix" nix-instantiate --parse "$f" >/dev/null
  done < <(find "$out" -name '*.nix')
  echo "OK: generated Nix parses"
else
  echo "SKIP: nix-instantiate not available, skipping parse check"
fi

exit $fail
