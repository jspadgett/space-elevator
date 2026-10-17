#!/usr/bin/env bash
# update.sh — bring a machine running a Space Elevator config up to
# date in one step: the modules to the newest release, nixpkgs (onto
# the next NixOS release when the modules moved to one), every other
# input with them. Then it builds without touching the running system,
# shows what would change, and switches only if you say so.
#
# A generated config's own ./update.sh runs this from the stable
# branch, so it is always the newest release's updater doing the work:
#
#   nix run github:jspadgett/space-elevator/stable#update -- \
#     --config /etc/nixos --host <name>
#
# Nothing it does is permanent until the switch. flake.nix and
# flake.lock are put back as they were if the build fails or you say
# no, and the previous generation stays in the boot menu regardless.
set -euo pipefail

CONFIG_DIR="/etc/nixos"
HOST=""
ASSUME_YES=0
DO_SWITCH=1
CHECK_ONLY=0
DO_COMMIT=1

usage() {
  cat <<'EOF'
Update a Space Elevator system: modules, nixpkgs and every other input.

  --config <path>   the configuration      (default: /etc/nixos)
  --host <name>     which host to build    (default: the only one, or
                                            the one named like this machine)
  --check           only say whether a new Space Elevator release is out
  --no-switch       update and build, leave the running system alone
  --no-commit       don't commit flake.nix / flake.lock afterwards
  --yes             don't ask; also accepts a NixOS release change
  --help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_DIR="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    --no-switch) DO_SWITCH=0; shift ;;
    --no-commit) DO_COMMIT=0; shift ;;
    --yes | -y) ASSUME_YES=1; shift ;;
    --help | -h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# gum is in the packaged app's closure. Run any other way — the test
# harness, a pipe — only its styling matters, so shim that.
if ! command -v gum >/dev/null 2>&1; then
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

NIX=(nix --extra-experimental-features "nix-command flakes")

# ── What are we updating? ───────────────────────────────────────────

[ -d "$CONFIG_DIR" ] || die "No configuration at $CONFIG_DIR. Point --config at yours."
CONFIG_DIR="$(cd "$CONFIG_DIR" && pwd)"
FLAKE="$CONFIG_DIR/flake.nix"
LOCK="$CONFIG_DIR/flake.lock"
[ -f "$FLAKE" ] || die "$CONFIG_DIR has no flake.nix."

# A config from before Space Elevator was an input carries its own
# copy of the modules. Nothing here can move those; the upgrade turns
# the config into one that can be updated, once.
if ! grep -qE '^[[:space:]]*space-elevator([[:space:]]*=|\.url)' "$FLAKE"; then
  if [ -f "$CONFIG_DIR/modules/default.nix" ]; then
    note "This config keeps its own copy of the Space Elevator modules, which"
    note "updating can't move. Switch it to the updatable layout once with:"
    note "  nix run github:jspadgett/space-elevator/stable#upgrade -- --config $CONFIG_DIR"
    note "Your switches, hardware config and own files carry across."
    exit 1
  fi
  die "$FLAKE has no space-elevator input — this doesn't look like a Space Elevator config."
fi

if [ -z "$HOST" ]; then
  HOSTS=()
  if [ -d "$CONFIG_DIR/hosts" ]; then
    while IFS= read -r d; do HOSTS+=("$(basename "$d")"); done \
      < <(find "$CONFIG_DIR/hosts" -mindepth 1 -maxdepth 1 -type d | sort)
  fi
  case "${#HOSTS[@]}" in
    0) die "No hosts under $CONFIG_DIR/hosts. Name one with --host." ;;
    1) HOST="${HOSTS[0]}" ;;
    *)
      HOST="$(hostname)"
      printf '%s\n' "${HOSTS[@]}" | grep -qxF "$HOST" \
        || die "Several hosts here (${HOSTS[*]}) and none is named $HOST. Pick one with --host."
      ;;
  esac
fi

# /etc/nixos may belong to root. Only the writes need the privilege;
# evaluating and building are fine as whoever runs this.
AS=()
if [ "$(id -u)" -ne 0 ] && { [ ! -w "$CONFIG_DIR" ] || { [ -e "$LOCK" ] && [ ! -w "$LOCK" ]; } || [ ! -w "$FLAKE" ]; }; then
  AS=(sudo)
fi

# ── Reading the lock ────────────────────────────────────────────────
# The space-elevator node in flake.lock says which release is in use
# and, through `original`, which branch it follows. release.nix in its
# source says what that release is. fetchTree on a locked node only
# reads the store; on `original` it asks the branch where it is now.

se_eval() {  # se_eval <locked|original> <nix expression over node, src, rel>
  SE_LOCK="$LOCK" SE_WHICH="$1" "${NIX[@]}" eval --impure --raw --expr "
    let
      lock = builtins.fromJSON (builtins.readFile (builtins.getEnv \"SE_LOCK\"));
      key = lock.nodes.\${lock.root}.inputs.\"space-elevator\";
      node = lock.nodes.\${key};
      ref = node.\${builtins.getEnv \"SE_WHICH\"};
      src = builtins.fetchTree (removeAttrs ref [ \"dir\" ]);
      rel = if builtins.pathExists (src + \"/release.nix\")
            then import (src + \"/release.nix\")
            else { version = \"unknown\"; nixosRelease = \"\"; };
    in toString ($2)"
}

lock_rev() {  # lock_rev <input name> — short revision, or empty
  SE_LOCK="$LOCK" SE_INPUT="$1" "${NIX[@]}" eval --impure --raw --expr '
    let
      lock = builtins.fromJSON (builtins.readFile (builtins.getEnv "SE_LOCK"));
      key = lock.nodes.${lock.root}.inputs.${builtins.getEnv "SE_INPUT"} or null;
      rev = if builtins.isString key then lock.nodes.${key}.locked.rev or "" else "";
    in builtins.substring 0 7 rev' 2>/dev/null || true
}

# A config with no lock yet has nothing to compare against; the first
# `nix flake update` below creates it.
OLD_VERSION="none yet"
OLD_SE_REV=""
OLD_NIXPKGS_REV=""
if [ -f "$LOCK" ] && grep -q '"space-elevator"' "$LOCK"; then
  OLD_VERSION="$(se_eval locked rel.version)"
  OLD_SE_REV="$(lock_rev space-elevator)"
  OLD_NIXPKGS_REV="$(lock_rev nixpkgs)"
fi

# ── --check: report and leave everything alone ──────────────────────

if [ "$CHECK_ONLY" = 1 ]; then
  [ -n "$OLD_SE_REV" ] || die "No lock entry for space-elevator yet — run ./update.sh."
  LATEST_VERSION="$(se_eval original rel.version)"
  LATEST_REV="$(se_eval original 'builtins.substring 0 7 (src.rev or "")')"
  if [ "$LATEST_REV" = "$OLD_SE_REV" ]; then
    good "Space Elevator $OLD_VERSION is the newest release."
  else
    note "Space Elevator $LATEST_VERSION is out (this machine has $OLD_VERSION)."
    note "Run ./update.sh to move to it."
  fi
  exit 0
fi

# ── Keep a way back ─────────────────────────────────────────────────
# Until the switch, every change here is to flake.nix and flake.lock.
# They go back exactly as they were unless we get as far as keeping
# them.

BACKUP="$(mktemp -d)"
cp "$FLAKE" "$BACKUP/flake.nix"
[ -f "$LOCK" ] && cp "$LOCK" "$BACKUP/flake.lock"
KEEP=0

restore() {
  [ "$KEEP" = 1 ] && return 0
  "${AS[@]}" cp "$BACKUP/flake.nix" "$FLAKE"
  if [ -f "$BACKUP/flake.lock" ]; then
    "${AS[@]}" cp "$BACKUP/flake.lock" "$LOCK"
  else
    "${AS[@]}" rm -f "$LOCK"
  fi
}
trap restore EXIT

flake_update() {  # flake_update [input...]
  "${AS[@]}" "${NIX[@]}" flake update --flake "$CONFIG_DIR" "$@"
}

# ── 1. Space Elevator ───────────────────────────────────────────────

header "Updating $HOST"
note "Checking for a new Space Elevator release..."
flake_update space-elevator

NEW_VERSION="$(se_eval locked rel.version)"
NEW_SE_REV="$(lock_rev space-elevator)"
NEW_RELEASE="$(se_eval locked rel.nixosRelease)"

# ── 2. The NixOS release, if the modules moved to a new one ─────────
# The config pins nixpkgs (and catppuccin) to a release by name.
# When Space Elevator moves on, those lines move with it — the modules
# are written for that release and won't necessarily evaluate on the
# old one. system.stateVersion is left alone; it is the release this
# machine was installed with, not the one it runs.

CURRENT_RELEASE="$(grep -E '^[[:space:]]*nixpkgs\.url[[:space:]]*=' "$FLAKE" \
  | grep -oE 'nixos-[0-9]{2}\.[0-9]{2}' | head -1 | sed 's/^nixos-//' || true)"

version_lt() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }

RELEASE_MOVED=""
if [ -z "$CURRENT_RELEASE" ]; then
  note "nixpkgs here doesn't follow a NixOS release branch, so it is left where it points."
elif [ -n "$NEW_RELEASE" ] && version_lt "$CURRENT_RELEASE" "$NEW_RELEASE"; then
  header "NixOS $CURRENT_RELEASE → $NEW_RELEASE"
  gum style --padding "0 2" \
    "Space Elevator $NEW_VERSION is written for NixOS $NEW_RELEASE, so this" \
    "update also moves the system to the new NixOS release. Expect a" \
    "larger download than usual; packages may change in ways that have" \
    "nothing to do with Space Elevator. Your system.stateVersion stays" \
    "as it is, and the current system stays in the boot menu."
  if ! confirm "Move to NixOS $NEW_RELEASE as part of this update?"; then
    note "Staying on NixOS $CURRENT_RELEASE means staying on Space Elevator $OLD_VERSION too."
    note "Nothing was changed."
    exit 0
  fi
  "${AS[@]}" sed -i -E \
    -e "/^[[:space:]]*nixpkgs\.url[[:space:]]*=/s/nixos-$CURRENT_RELEASE/nixos-$NEW_RELEASE/" \
    -e "/catppuccin/s/release-$CURRENT_RELEASE/release-$NEW_RELEASE/" \
    "$FLAKE"
  RELEASE_MOVED="$CURRENT_RELEASE → $NEW_RELEASE"
elif [ -n "$NEW_RELEASE" ] && version_lt "$NEW_RELEASE" "$CURRENT_RELEASE"; then
  note "This config is on NixOS $CURRENT_RELEASE, ahead of the $NEW_RELEASE Space Elevator is written for. Leaving it there."
fi

# ── 3. Everything else ──────────────────────────────────────────────

note "Updating nixpkgs and the other inputs..."
flake_update

NEW_NIXPKGS_REV="$(lock_rev nixpkgs)"

# ── What changed ────────────────────────────────────────────────────

if [ "$OLD_SE_REV" = "$NEW_SE_REV" ]; then
  SE_LINE="$NEW_VERSION (already the newest)"
else
  SE_LINE="$OLD_VERSION → $NEW_VERSION"
fi
if [ "$OLD_NIXPKGS_REV" = "$NEW_NIXPKGS_REV" ]; then
  NIXPKGS_LINE="${NEW_NIXPKGS_REV:-unchanged} (unchanged)"
else
  NIXPKGS_LINE="${OLD_NIXPKGS_REV:-none} → $NEW_NIXPKGS_REV"
fi

gum style --padding "0 2" \
  "Space Elevator  $SE_LINE" \
  "NixOS           ${RELEASE_MOVED:-${CURRENT_RELEASE:-as configured}}" \
  "nixpkgs         $NIXPKGS_LINE"

if [ "$OLD_SE_REV" != "$NEW_SE_REV" ] && [ "$NEW_VERSION" != "unknown" ]; then
  note "What's new: https://github.com/jspadgett/space-elevator/releases/tag/v$NEW_VERSION"
fi

# ── Build, without touching the running system ──────────────────────

header "Building (nothing is activated yet)"
WORK="$(mktemp -d)"
if ! (cd "$WORK" && nixos-rebuild build --flake "$CONFIG_DIR#$HOST"); then
  note "flake.nix and flake.lock are back as they were; the running system was never touched."
  die "The build failed — the error is above. Try again later, or report it if it persists."
fi
RESULT="$WORK/result"

if [ -e /run/current-system ] \
   && [ "$(readlink -f "$RESULT")" = "$(readlink -f /run/current-system)" ]; then
  KEEP=1
  good "Already up to date — the new build is the system you are running."
  exit 0
fi

if command -v nvd >/dev/null 2>&1 && [ -e /run/current-system ]; then
  header "What would change"
  nvd diff /run/current-system "$RESULT" || true
fi

if [ "$DO_SWITCH" = 0 ]; then
  KEEP=1
  good "Built. flake.lock now describes the update; the running system is unchanged."
  note "To switch to it: sudo nixos-rebuild switch --flake $CONFIG_DIR#$HOST"
  exit 0
fi

# ── Switch ──────────────────────────────────────────────────────────

if ! confirm "Switch to the updated system now?"; then
  note "Nothing was changed."
  exit 0
fi

# From here the new lock is the one the system will run; a failed
# switch is undone by the boot menu, not by putting the files back.
KEEP=1
if ! sudo nixos-rebuild switch --flake "$CONFIG_DIR#$HOST"; then
  gum style --foreground 1 "The switch reported an error — scroll up for details."
  note "The previous system is still in the boot menu. To put the config back too:"
  note "  sudo cp $BACKUP/flake.nix $BACKUP/flake.lock $CONFIG_DIR/"
  exit 1
fi

# Record it, when the config is a git repository: one commit holding
# exactly this update, which `git revert` takes back out.
if [ "$DO_COMMIT" = 1 ] && git -C "$CONFIG_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IDENT=()
  git -C "$CONFIG_DIR" config user.email >/dev/null 2>&1 \
    || IDENT=(-c "user.name=Space Elevator update" -c "user.email=update@space-elevator.invalid")
  MSG="update: Space Elevator $SE_LINE"
  [ -n "$RELEASE_MOVED" ] && MSG="$MSG, NixOS $RELEASE_MOVED"
  "${AS[@]}" git -C "$CONFIG_DIR" add flake.nix flake.lock
  if "${AS[@]}" git -C "$CONFIG_DIR" "${IDENT[@]}" commit -q -m "$MSG" -- flake.nix flake.lock 2>/dev/null; then
    note "Committed: $MSG"
  fi
fi

gum style --border double --border-foreground 2 --padding "1 3" --margin "1 0" --align center \
  "Updated." \
  "" \
  "If anything is wrong, reboot and choose the" \
  "previous generation in the boot menu."
