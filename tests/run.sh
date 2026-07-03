#!/usr/bin/env bash
# Non-interactive test harness: generate a config for every DE with all
# flavors enabled and assert the output is complete and correctly pinned.
set -euo pipefail
cd "$(dirname "$0")/.."

export SE_NONINTERACTIVE=1
export SE_HOSTNAME=citest SE_USERNAME=ci SE_TIMEZONE=Etc/UTC
export SE_LOCALE=en_US.UTF-8 SE_KEYMAP=us SE_GPU=AMD
export SE_FLAVORS="gaming,development,theming,kdeconnect"

fail=0
for de in "KDE Plasma" "GNOME" "COSMIC" "Hyprland"; do
  out=$(mktemp -d)/cfg
  SE_DE="$de" SE_OUTDIR="$out" MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null

  for f in flake.nix flake/hosts.nix update.sh README.md \
           hosts/citest/citest.nix hosts/citest/configuration.nix \
           hosts/citest/hardware-configuration.nix; do
    [ -f "$out/$f" ] || { echo "FAIL ($de): missing $f"; fail=1; }
  done
  [ -x "$out/update.sh" ] || { echo "FAIL ($de): update.sh not executable"; fail=1; }
  grep -q 'nixos-26.05' "$out/flake.nix" || { echo "FAIL ($de): wrong nixpkgs pin"; fail=1; }
  grep -q 'catppuccin' "$out/flake.nix" || { echo "FAIL ($de): theming flavor missing input"; fail=1; }
  grep -q 'en_US.UTF-8' "$out/modules/common/base-locale.nix" || { echo "FAIL ($de): locale not substituted"; fail=1; }
  grep -qE '@(USERNAME|LOCALE|KB_LAYOUT)@' -r "$out/modules" && { echo "FAIL ($de): unsubstituted placeholder"; fail=1; }
  grep -q 'steam.nix' "$out/hosts/citest/citest.nix" || { echo "FAIL ($de): gaming flavor missing"; fail=1; }
  [ -d "$out/.git" ] || { echo "FAIL ($de): git repo not initialized"; fail=1; }
  echo "OK: $de"
done

# A config with no flavors must not reference catppuccin
out=$(mktemp -d)/cfg
SE_DE="GNOME" SE_FLAVORS="" SE_OUTDIR="$out" MODULE_SOURCE="$PWD/modules" bash scaffold.sh >/dev/null
grep -q 'catppuccin' "$out/flake.nix" && { echo "FAIL: catppuccin input present without theming"; fail=1; }
echo "OK: no-flavor config"

exit $fail
