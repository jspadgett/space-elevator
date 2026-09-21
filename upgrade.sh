#!/usr/bin/env bash
# upgrade.sh — move a machine that already runs a Space Elevator config
# onto the current module set.
#
#   nix run github:jspadgett/space-elevator#upgrade
#
# It reads the existing configuration, regenerates it with today's
# modules, and carries across the things the wizard cannot know: the
# hardware configuration, system.stateVersion, the declared password,
# and which features were switched on. Then it builds — without
# touching the running system — and only switches if you say so.
#
# Nothing is deleted. The old configuration is moved aside, and the
# previous system generation stays in the boot menu either way.
#
# The long-hand version of what this does is docs/UPGRADING.md.
#
# SCAFFOLD_BIN is injected by flake.nix; the fallback covers dev runs.
set -euo pipefail

CONFIG_DIR="/etc/nixos"
OUTPUT_DIR=""
ASSUME_YES=0
DO_BUILD=1
DO_SWITCH=1
STAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'EOF'
Upgrade an existing Space Elevator system to the current modules.

  --config <path>   configuration to upgrade   (default: /etc/nixos)
  --output <path>   where to build the new one (default: <config>.new)
  --yes             accept what it detects, don't prompt
  --no-build        generate only; don't compile
  --no-switch       generate and build; don't activate or move anything
  --help

With --no-switch nothing outside <output> is touched, so it is a safe
way to see what you would get.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_DIR="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --yes | -y) ASSUME_YES=1; shift ;;
    --no-build) DO_BUILD=0; DO_SWITCH=0; shift ;;
    --no-switch) DO_SWITCH=0; shift ;;
    --help | -h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

OUTPUT_DIR="${OUTPUT_DIR:-${CONFIG_DIR%/}.new}"

# Without a terminal to prompt at, gum's styling is the only thing we
# need from it — shim it so the script runs in CI and over pipes.
if [ "$ASSUME_YES" = 1 ] && ! command -v gum >/dev/null 2>&1; then
  gum() {
    if [ "$1" = "style" ]; then
      shift
      while [ $# -gt 0 ] && [[ "$1" == --* ]]; do shift 2; done
      printf '%s\n' "$@"
    else
      return 1
    fi
  }
fi

header() { gum style --border rounded --border-foreground 6 --padding "0 2" --margin "1 0" "$1"; }
note()   { gum style --foreground 3 "$1"; }
good()   { gum style --foreground 2 "$1"; }
die()    { gum style --foreground 1 "$1"; exit 1; }

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  gum confirm "$1"
}

# Make a directory exist and belong to this user. The target may sit
# on a root-owned filesystem — /etc/nixos.new beside a real config,
# /mnt/etc/nixos in the installer — and mkdir -p succeeds on a
# directory that already exists, so writability is what decides.
ensure_writable_dir() {
  if ! mkdir -p "$1" 2>/dev/null || [ ! -w "$1" ]; then
    sudo mkdir -p "$1"
    sudo chown "$(id -u):$(id -g)" "$1"
    sudo chmod u+rwx "$1"
  fi
}

# The generator, with its vendored modules.
if [ -n "${SCAFFOLD_BIN:-}" ]; then
  SCAFFOLD=("$SCAFFOLD_BIN")
else
  SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  SCAFFOLD=(bash "$SELF_DIR/scaffold.sh")
fi

# ── Read the existing configuration ─────────────────────────────────

[ -d "$CONFIG_DIR" ] || die "No configuration at $CONFIG_DIR. Point --config at yours."
[ -f "$CONFIG_DIR/flake.nix" ] || die "$CONFIG_DIR has no flake.nix — this doesn't look like a Space Elevator config."
[ -d "$CONFIG_DIR/hosts" ] || die "$CONFIG_DIR has no hosts/ directory — this doesn't look like a Space Elevator config."

if [ "$DO_BUILD" = 1 ] && [ ! -e /etc/NIXOS ]; then
  die "This doesn't look like a running NixOS system. Use --no-build to generate a config anyway."
fi

HOSTS=()
while IFS= read -r d; do HOSTS+=("$(basename "$d")"); done \
  < <(find "$CONFIG_DIR/hosts" -mindepth 1 -maxdepth 1 -type d | sort)

case "${#HOSTS[@]}" in
  0) die "No hosts found under $CONFIG_DIR/hosts." ;;
  1) HOSTNAME="${HOSTS[0]}" ;;
  *)
    if [ "$ASSUME_YES" = 1 ]; then
      HOSTNAME="$(hostname)"
      printf '%s\n' "${HOSTS[@]}" | grep -qxF "$HOSTNAME" \
        || die "Several hosts here (${HOSTS[*]}) and none matches $(hostname). Upgrade them one at a time with --config."
    else
      HOSTNAME=$(gum choose --header "Which host is this machine?" "${HOSTS[@]}")
    fi
    ;;
esac

HOST_DIR="$CONFIG_DIR/hosts/$HOSTNAME"
OLD_CONFIGURATION="$HOST_DIR/configuration.nix"
OLD_HARDWARE="$HOST_DIR/hardware-configuration.nix"
[ -f "$OLD_CONFIGURATION" ] || die "Expected $OLD_CONFIGURATION to exist."

# The current layout keeps this machine's choices in a switches file
# next to its configuration. That file is authoritative: its tree is
# carried across and only the module set is replaced. The older
# layouts have nowhere to read choices from, so they are regenerated
# from what detection can find.
CURRENT_LAYOUT=0
[ -f "$HOST_DIR/space-elevator.nix" ] && CURRENT_LAYOUT=1

# Everything the old config says about itself, in one haystack. This
# reads both layouts: the old one imported module files, the current
# one sets options, and the greps below look for either.
#
# Comments are stripped first, and that is not cosmetic. The switches
# file lists every option you did *not* pick as a commented line, so
# searching the raw text would read a GNOME machine as a Plasma one
# with every flavor enabled.
uncommented() { sed -E 's/#.*$//' "$@"; }

HAYSTACK="$(uncommented "$CONFIG_DIR"/hosts/"$HOSTNAME"/*.nix "$CONFIG_DIR"/flake.nix 2>/dev/null || true)"

# First capture group of the first match, or empty.
extract() {
  local pattern="$1" text="$2"
  [[ "$text" =~ $pattern ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

# Was this feature on, in either layout?
# A here-string rather than `printf | grep`: grep -q exits at the
# first match, and under `set -o pipefail` a SIGPIPE'd printf turns a
# successful match into a non-zero return — a silent false negative.
had() { grep -qE "$1" <<<"$HAYSTACK"; }

STATE_VERSION="$(extract 'system\.stateVersion = "([^"]+)"' "$HAYSTACK")"
TIMEZONE="$(extract 'time\.timeZone = "([^"]+)"' "$HAYSTACK")"
USERNAME="$(extract 'users\.users\.([A-Za-z0-9_-]+) = \{' "$HAYSTACK")"
[ -n "$USERNAME" ] || USERNAME="$(extract 'user\.name = "([^"]+)"' "$HAYSTACK")"
[ -n "$USERNAME" ] || USERNAME="${SUDO_USER:-$USER}"

# Locale and keyboard: a module in the old layout, the switches file
# in the current one. The old-layout module carried the values
# directly; the current one only declares defaults, so a match there
# is harmless either way.
LOCALE_HAYSTACK="$HAYSTACK
$(uncommented "$CONFIG_DIR"/modules/common/*.nix 2>/dev/null || true)"

# Three spellings have shipped: the module carried the value directly
# (oldest), then settings.nix had a bare `locale`, and now it is
# `locale.defaultLocale`. Try them newest first.
LOCALE="$(extract 'defaultLocale = "([^"]+)"' "$LOCALE_HAYSTACK")"
[ -n "$LOCALE" ] || LOCALE="$(extract 'locale = "([^"]+)"' "$LOCALE_HAYSTACK")"
[ -n "$LOCALE" ] || LOCALE="${LANG%%:*}"
[ -n "$LOCALE" ] || LOCALE="en_US.UTF-8"

# Likewise: xkb.layout, then keyboard.layout, now keyboardLayout.
KB_LAYOUT="$(extract 'keyboardLayout = "([^"]+)"' "$LOCALE_HAYSTACK")"
[ -n "$KB_LAYOUT" ] || KB_LAYOUT="$(extract 'keyboard\.layout = "([^"]+)"' "$LOCALE_HAYSTACK")"
[ -n "$KB_LAYOUT" ] || KB_LAYOUT="$(extract 'xkb\.layout = "([^"]+)"' "$LOCALE_HAYSTACK")"
[ -n "$KB_LAYOUT" ] || KB_LAYOUT="us"

DE=""
for de in plasma gnome cosmic hyprland; do
  if had "modules/desktop/$de\.nix|desktop\.$de\.enable[[:space:]]*=[[:space:]]*true"; then
    case "$de" in
      plasma)   DE="KDE Plasma" ;;
      gnome)    DE="GNOME" ;;
      cosmic)   DE="COSMIC" ;;
      hyprland) DE="Hyprland" ;;
    esac
    break
  fi
done
[ -n "$DE" ] || DE="KDE Plasma"

# Either `gpu.<vendor>.enable = true;` or the block form
# `gpu.<vendor> = {`, which is what the wizard writes for a PRIME
# laptop — the block form used to be unmatchable, so hybrid machines
# upgraded to a config with no driver at all.
gpu_on() { had "gpu\.$1(\.enable[[:space:]]*=[[:space:]]*true|[[:space:]]*=[[:space:]]*\{)"; }

GPU="None / VM"
if   had "modules/gpu/nvidia\.nix"    || gpu_on nvidia; then GPU="NVIDIA"
elif had "modules/gpu/amdgpu\.nix"    || gpu_on amd;    then GPU="AMD"
elif had "modules/gpu/intel-gpu\.nix" || gpu_on intel;  then GPU="Intel"
fi

TLP=0
had "modules/tuning/tlp\.nix|tuning\.tlp\.enable[[:space:]]*=[[:space:]]*true" && TLP=1

FLAVORS=""
had "modules/apps/(docker|virtualisation)\.nix|development\.enable[[:space:]]*=[[:space:]]*true" \
  && FLAVORS="development"
if had "modules/desktop/kdeconnect\.nix|desktop\.kdeconnect\.enable[[:space:]]*=[[:space:]]*true"; then
  FLAVORS="${FLAVORS:+$FLAVORS,}kdeconnect"
fi

# PRIME: carried over if the old config set bus IDs, which means this
# is a hybrid laptop already set up for offload. In the old layout
# they were edited into the module itself, so look there too — and
# anchor the match, so the option's own declaration and examples in
# the current module don't count.
PRIME=0
PRIME_HAYSTACK="$HAYSTACK
$(uncommented "$CONFIG_DIR"/modules/gpu/nvidia.nix 2>/dev/null || true)"
if grep -qE '^[[:space:]]*nvidiaBusId[[:space:]]*=[[:space:]]*"PCI:' <<<"$PRIME_HAYSTACK"; then
  PRIME=1
fi

# Detection greps text, so it only knows the spellings we thought of —
# a formatter that breaks `= {` onto its own line is enough to miss.
# A bus ID naming an NVIDIA card for offload is proof the driver
# belongs, however the enabling attribute is laid out. Only the
# regenerated layouts need it; the current layout carries its own
# switches across.
if [ "$CURRENT_LAYOUT" = 0 ] && [ "$PRIME" = 1 ] && [ "$GPU" != "NVIDIA" ]; then
  GPU="NVIDIA"
fi

# The declared password, so the upgrade doesn't silently change it.
PASSWORD_LINE="$(grep -oE '(hashedPassword|initialPassword) = "[^"]*";' "$OLD_CONFIGURATION" | head -1 || true)"

# ── Confirm ─────────────────────────────────────────────────────────

header "Upgrading $HOSTNAME"

if [ "$CURRENT_LAYOUT" = 1 ]; then
  gum style --padding "0 2" \
    "Reading    $CONFIG_DIR" \
    "Building   $OUTPUT_DIR" \
    "" \
    "host            $HOSTNAME" \
    "configuration   carried across unchanged" \
    "module set      replaced with this release" \
    "stateVersion    ${STATE_VERSION:-as written in your config}" \
    "password        as written in your config"
else
  gum style --padding "0 2" \
    "Reading    $CONFIG_DIR" \
    "Building   $OUTPUT_DIR" \
    "" \
    "host            $HOSTNAME" \
    "user            $USERNAME" \
    "desktop         $DE" \
    "GPU             $GPU$( [ "$PRIME" = 1 ] && echo "  (PRIME offload)" )" \
    "timezone        ${TIMEZONE:-detected}" \
    "locale          $LOCALE, keyboard $KB_LAYOUT" \
    "laptop power    $( [ "$TLP" = 1 ] && echo "TLP" || echo "no" )" \
    "extras          ${FLAVORS:-none}" \
    "stateVersion    ${STATE_VERSION:-NOT FOUND}" \
    "password        $( [ -n "$PASSWORD_LINE" ] && echo "carried over" || echo "unchanged" )"
fi

# Only the regenerated layouts write a stateVersion; the current
# layout keeps whatever its own configuration.nix declares.
if [ "$CURRENT_LAYOUT" = 0 ] && [ -z "$STATE_VERSION" ]; then
  note "No system.stateVersion found in the old config. That value must not change, so I can't safely continue."
  die "Set it in $OLD_CONFIGURATION, or upgrade by hand: docs/UPGRADING.md"
fi

note "Gaming (Steam, GameMode, the launchers), Firefox and Catppuccin theming are standard now, so expect several GB of downloads."

confirm "Generate the new configuration?" || { note "Nothing was written."; exit 0; }

# ── Generate ────────────────────────────────────────────────────────

if [ -e "$OUTPUT_DIR" ]; then
  confirm "$OUTPUT_DIR already exists. Replace it?" || die "Stopping; nothing was written."
  rm -rf "${OUTPUT_DIR:?}"
fi

# The scaffold always writes to a temp directory. On the current
# layout that tree is the reference for the review diff and the source
# of the replaced module set; on the older layouts it is the output.
REFERENCE_DIR="$(mktemp -d)/reference"

SE_NONINTERACTIVE=1 \
SE_HOSTNAME="$HOSTNAME" \
SE_USERNAME="$USERNAME" \
SE_TIMEZONE="${TIMEZONE:-}" \
SE_LOCALE="$LOCALE" \
SE_KEYMAP="$KB_LAYOUT" \
SE_GPU="$GPU" \
SE_DE="$DE" \
SE_TLP="$TLP" \
SE_PRIME="$PRIME" \
SE_FLAVORS="$FLAVORS" \
SE_OUTDIR="$REFERENCE_DIR" \
  "${SCAFFOLD[@]}" >/dev/null

# What Space Elevator ships and therefore owns. Everything else in the
# tree belongs to whoever wrote it.
SE_OWNED=(
  modules/apps
  modules/common
  modules/desktop
  modules/development
  modules/gaming
  modules/gpu
  modules/network
  modules/tuning
  modules/default.nix
  README.md
  update.sh
)

ensure_writable_dir "$OUTPUT_DIR"

if [ "$CURRENT_LAYOUT" = 1 ]; then
  cp -a "$CONFIG_DIR/." "$OUTPUT_DIR/"
  for owned in "${SE_OWNED[@]}"; do
    rm -rf "${OUTPUT_DIR:?}/$owned"
    if [ -e "$REFERENCE_DIR/$owned" ]; then
      mkdir -p "$(dirname "$OUTPUT_DIR/$owned")"
      cp -a "$REFERENCE_DIR/$owned" "$OUTPUT_DIR/$owned"
    fi
  done
else
  cp -a "$REFERENCE_DIR/." "$OUTPUT_DIR/"
fi

NEW_HOST_DIR="$OUTPUT_DIR/hosts/$HOSTNAME"
NEW_CONFIGURATION="$NEW_HOST_DIR/configuration.nix"

# ── Carry across what the wizard couldn't know ──────────────────────
#
# Steps 2 to 4 rebuild the host files from detection, so they apply
# only to the regenerated layouts. The current layout already has the
# user's own copies of all three.

# 1. The hardware configuration, as it is. Regenerating it would lose
#    anything you hand-edited (LUKS devices, btrfs subvolume options),
#    and this file is what currently boots the machine.
HARDWARE_NOTE="copied from the old config"
if [ -f "$OLD_HARDWARE" ] && ! grep -q "^# PLACEHOLDER" "$OLD_HARDWARE"; then
  cp "$OLD_HARDWARE" "$NEW_HOST_DIR/hardware-configuration.nix"
else
  HARDWARE_NOTE="regenerated from this machine (the old one was a placeholder)"
  HW_TEXT=""
  if command -v nixos-generate-config >/dev/null 2>&1; then
    HW_TEXT="$(nixos-generate-config --show-hardware-config 2>/dev/null || true)"
    [ -n "$HW_TEXT" ] || HW_TEXT="$(sudo -n nixos-generate-config --show-hardware-config 2>/dev/null || true)"
  fi
  if [ -n "$HW_TEXT" ]; then
    printf '%s\n' "$HW_TEXT" > "$NEW_HOST_DIR/hardware-configuration.nix"
  else
    HARDWARE_NOTE="still a placeholder — replace it before you install anywhere"
  fi
fi

# 2. stateVersion. Records the release this machine was installed
#    with; some services read it to decide on-disk formats, so it must
#    survive every upgrade.
if [ "$CURRENT_LAYOUT" = 0 ]; then
  sed -i "s|system.stateVersion = \"[^\"]*\"|system.stateVersion = \"$STATE_VERSION\"|" "$NEW_CONFIGURATION"
fi

# 3. The declared password, so nobody is locked out by a rebuild.
if [ "$CURRENT_LAYOUT" = 0 ] && [ -n "$PASSWORD_LINE" ]; then
  ESCAPED="${PASSWORD_LINE//\\/\\\\}"
  ESCAPED="${ESCAPED//|/\\|}"
  sed -i -E "s|(hashedPassword\|initialPassword) = \"[^\"]*\";.*|$ESCAPED|" "$NEW_CONFIGURATION"
fi

# 4. Anything of yours the wizard doesn't write. Too varied to merge
#    safely, so it gets reported rather than guessed at.
CUSTOM_MODULES=()
if [ "$CURRENT_LAYOUT" = 0 ] && [ -d "$CONFIG_DIR/modules" ]; then
  while IFS= read -r f; do
    rel="${f#"$CONFIG_DIR"/modules/}"
    [ -e "$OUTPUT_DIR/modules/$rel" ] || CUSTOM_MODULES+=("$rel")
  done < <(find "$CONFIG_DIR/modules" -name '*.nix' | sort)
fi

DIFF_FILE="$OUTPUT_DIR/UPGRADE-REVIEW.diff"
if [ "$CURRENT_LAYOUT" = 1 ]; then
  # Your files against the ones the wizard would have written. This is
  # where a change to the templates or the module set shows up.
  {
    for rel in \
      "hosts/$HOSTNAME/configuration.nix" \
      "hosts/$HOSTNAME/space-elevator.nix" \
      "hosts/$HOSTNAME/$HOSTNAME.nix"
    do
      echo "── $rel — yours, then this release ──"
      diff -u "$CONFIG_DIR/$rel" "$REFERENCE_DIR/$rel" || true
      echo
    done
    echo "── modules/ — yours, then this release ──"
    diff -ru "$CONFIG_DIR/modules" "$REFERENCE_DIR/modules" || true
  } > "$DIFF_FILE" 2>/dev/null
else
  diff -u "$OLD_CONFIGURATION" "$NEW_CONFIGURATION" > "$DIFF_FILE" 2>/dev/null || true
fi

OTHER_HOSTS=()
for h in "${HOSTS[@]}"; do
  [ "$h" = "$HOSTNAME" ] || OTHER_HOSTS+=("$h")
done

{
  echo "# Upgrade review — $HOSTNAME"
  echo
  echo "Generated $STAMP by \`space-elevator#upgrade\`, from $CONFIG_DIR."
  echo
  if [ "$CURRENT_LAYOUT" = 1 ]; then
    echo "## Carried across unchanged"
    echo
    echo "Your configuration reached the new directory as it was:"
    echo "hosts/, flake.nix, flake.lock, the git history and anything"
    echo "else you keep there. Your switches in"
    echo "hosts/$HOSTNAME/space-elevator.nix are exactly as you left them."
    echo
    echo "Replaced with this release:"
    echo
    echo "- modules/ — the eight Space Elevator categories and default.nix"
    echo "- README.md and update.sh"
    echo
    echo "Anything else under modules/ is yours and was left alone."
    echo
    echo "## Worth your eyes"
    echo
    echo "\`UPGRADE-REVIEW.diff\` sets each of your host files against what"
    echo "the wizard writes today, then your old modules/ against the new"
    echo "one. None of it has been applied — it is there so you can pick"
    echo "up anything you want."
    echo
    echo "Because your flake.lock carried over, the inputs are still"
    echo "pinned where they were. Run \`./update.sh\` when you want to move"
    echo "them."
  else
    echo "## Carried across for you"
    echo
    echo "- hardware-configuration.nix — $HARDWARE_NOTE"
    echo "- system.stateVersion — kept at \"$STATE_VERSION\""
    if [ -n "$PASSWORD_LINE" ]; then
      echo "- the declared password line, so your login is unchanged"
    fi
    echo "- desktop ($DE), GPU ($GPU), extras (${FLAVORS:-none})"
    if [ "$PRIME" = 1 ]; then
      echo "- PRIME offload, with bus IDs re-read from this machine — worth"
      echo "  checking them against \`lspci | grep -E 'VGA|3D'\`"
    fi
    echo
    echo "## Not carried across"
    echo
    echo "- flake.lock — the inputs resolve fresh, so this upgrade moves"
    echo "  them. Your old lock is in the backup beside this directory."
    echo "- the git history — the new tree starts its own; yours stays"
    echo "  with the backup."
    if [ "${#OTHER_HOSTS[@]}" -gt 0 ]; then
      echo "- the other hosts here (${OTHER_HOSTS[*]}). Upgrade each of them"
      echo "  on its own with \`--config\`."
    fi
    echo
    echo "## Worth your eyes"
    echo
    echo "\`UPGRADE-REVIEW.diff\` is your old configuration.nix against the"
    echo "new one. Anything you added by hand — extra packages, extra users,"
    echo "services, boot tweaks — shows up there as a removal, and needs"
    echo "copying into hosts/$HOSTNAME/configuration.nix."
    echo
    echo "Firewall ports have moved: \`networking.firewall.allowedTCPPorts\`"
    echo "is now \`spaceElevator.network.firewall.allowedTCPPorts\`, set in"
    echo "hosts/$HOSTNAME/space-elevator.nix."
    if [ "${#CUSTOM_MODULES[@]}" -gt 0 ]; then
      echo
      echo "## Your own modules"
      echo
      echo "These were in the old modules/ and are not part of the Space"
      echo "Elevator set, so they were not copied. Bring them over and add"
      echo "them to the modules list in hosts/$HOSTNAME/$HOSTNAME.nix:"
      echo
      printf -- "- %s\n" "${CUSTOM_MODULES[@]}"
    fi
    echo
    echo "## What is on now that wasn't before"
    echo
    echo "Steam with Proton-GE, gamescope and protontricks; Heroic, Lutris"
    echo "and ProtonUp-Qt; GameMode and MangoHud; controller support;"
    echo "Firefox; Vesktop; Catppuccin theming. Each is one line to remove"
    echo "in hosts/$HOSTNAME/space-elevator.nix."
  fi
} > "$OUTPUT_DIR/UPGRADE-NOTES.md"

git -C "$OUTPUT_DIR" add -A 2>/dev/null || true

good "Generated $OUTPUT_DIR"
note "Read $OUTPUT_DIR/UPGRADE-NOTES.md — it lists what carried over and what didn't."
if [ "${#CUSTOM_MODULES[@]}" -gt 0 ]; then
  note "Found ${#CUSTOM_MODULES[@]} module(s) of your own that were not copied; see the notes."
fi

[ "$DO_BUILD" = 1 ] || exit 0

# ── Build, without touching the running system ──────────────────────

header "Building (nothing is activated yet)"
note "This is where the downloading happens. A failure here leaves your running system completely untouched."

if ! nixos-rebuild build --flake "$OUTPUT_DIR#$HOSTNAME"; then
  die "Build failed. Your system is unchanged. Fix what it reported in $OUTPUT_DIR and re-run with --config $CONFIG_DIR."
fi

good "Built successfully."

if command -v nvd >/dev/null 2>&1 && [ -e ./result ]; then
  header "What would change"
  nvd diff /run/current-system ./result || true
fi

[ "$DO_SWITCH" = 1 ] || {
  note "Stopping before activation, as asked. To go ahead later:"
  note "  sudo nixos-rebuild switch --flake $OUTPUT_DIR#$HOSTNAME"
  exit 0
}

# ── Switch ──────────────────────────────────────────────────────────

confirm "Switch to the new system now?" || {
  note "Left as it is. The new configuration is at $OUTPUT_DIR; switch when you're ready:"
  note "  sudo nixos-rebuild switch --flake $OUTPUT_DIR#$HOSTNAME"
  exit 0
}

BACKUP_DIR="${CONFIG_DIR%/}.backup-$STAMP"
sudo mv "$CONFIG_DIR" "$BACKUP_DIR"
sudo mv "$OUTPUT_DIR" "$CONFIG_DIR"
good "Old configuration moved to $BACKUP_DIR"

if sudo nixos-rebuild switch --flake "$CONFIG_DIR#$HOSTNAME"; then
  gum style --border double --border-foreground 2 --padding "1 3" --margin "1 0" --align center \
    "Upgraded." \
    "" \
    "Log out and back in to pick up the new session." \
    "If anything is wrong, reboot and choose the" \
    "previous generation in the boot menu."
  note "Old configuration: $BACKUP_DIR"
  note "Still to read: $CONFIG_DIR/UPGRADE-NOTES.md"
else
  gum style --foreground 1 "The switch reported an error — scroll up for details."
  note "Your previous system is still in the boot menu, and the old configuration is at $BACKUP_DIR:"
  note "  sudo nixos-rebuild switch --flake $BACKUP_DIR#$HOSTNAME"
  exit 1
fi
