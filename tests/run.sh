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

has_line() { grep -qF "$2" "$1"; }
lacks_line() { ! grep -qF "$2" "$1"; }

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
  check "$de" "user not set" has_line "$se" 'user = "ci";'
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
