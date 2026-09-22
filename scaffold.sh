#!/usr/bin/env bash
# space-elevator — opinionated NixOS desktop generator
# Answer a few questions, get a complete desktop flake with distro-grade defaults.
#
# Non-interactive mode (for CI / scripting): set SE_NONINTERACTIVE=1 and any of
#   SE_HOSTNAME SE_USERNAME SE_PASSWORD SE_TIMEZONE SE_LOCALE SE_KEYMAP
#   SE_OUTDIR SE_GPU (AMD|Intel|NVIDIA|None) SE_DE ("KDE Plasma"|GNOME|COSMIC|Hyprland)
#   SE_FLAVORS (comma list of: development,kdeconnect — gaming and
#     theming are standard and not optional)
#   SE_TLP=1|0 to override the battery check
#   SE_HANDHELD=1|0 to override handheld detection (DMI product name)
#   SE_PRIME=1 to set up PRIME offload from this machine's detected
#     bus IDs (non-interactive defaults to off, since the machine
#     running the wizard may not be the target)
#
# The generated config vendors the whole module set and switches
# features on through options in hosts/<name>/space-elevator.nix.
#
# MODULE_SOURCE is injected by flake.nix; the fallback covers standalone dev runs.
set -euo pipefail
MODULE_SOURCE="${MODULE_SOURCE:-$(cd "$(dirname "$0")" && pwd)/modules}"
SE_NIXPKGS_REV="${SE_NIXPKGS_REV:-}"
NONINT="${SE_NONINTERACTIVE:-0}"

# In non-interactive environments without gum (CI), shim `gum style` to echo.
# All style flags we use take a value, so drop flag+value pairs and print.
if [ "$NONINT" = 1 ] && ! command -v gum >/dev/null 2>&1; then
  gum() {
    if [ "$1" = "style" ]; then
      shift
      while [ $# -gt 0 ] && [[ "$1" == --* ]]; do shift 2; done
      printf '%s\n' "$@"
    else
      echo "gum required for interactive prompts" >&2
      return 1
    fi
  }
fi

# ── Helpers ─────────────────────────────────────────────────────────

header() {
  gum style --border rounded --border-foreground 6 --padding "0 2" --margin "1 0" "$1"
}

note() { gum style --foreground 3 "$1"; }

die() { gum style --foreground 1 "$1"; exit 1; }

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

# gum choose exits nonzero on ESC/empty; treat as "nothing selected"
pick_many() {
  gum choose --no-limit --header "$1" "${@:2}" || true
}

pick_one() {
  gum choose --header "$1" "${@:2}"
}

# Exact-line match against gum's newline-separated selections
has() { grep -qxF "$2" <<<"$1"; }

# Confirm with a non-interactive default: prompt_confirm "question" y|n
prompt_confirm() {
  if [ "$NONINT" = 1 ]; then [ "${2:-y}" = "y" ]; else gum confirm "$1"; fi
}

GENERATING=false
DISK_TOUCHED=false
on_err() {
  echo
  if [ "$GENERATING" = true ]; then
    gum style --foreground 1 "Generation failed — $OUTDIR may be incomplete."
  elif [ "$DISK_TOUCHED" = true ]; then
    gum style --foreground 1 "Disk setup failed — $TARGET_DISK has been modified. Re-run the wizard to try again."
  else
    note "Aborted — nothing was written."
  fi
}
trap on_err ERR

if [ "$NONINT" != 1 ]; then
  echo ""
  gum style \
    --border double --border-foreground 6 \
    --padding "1 3" --margin "0 2" --align center \
    "🚀 SPACE ELEVATOR" \
    "" \
    "Your NixOS desktop, built to order:" \
    "a few quick questions, distro-grade defaults."
fi

# ── Installer environment (ISO): network + disk, fully guided ──────

INSTALL_MODE=false
TARGET_DISK=""
# The live installer ISO is identifiable by its read-only squashfs
# store / medium mount — an installed system has neither, even though
# it also has nixos-install on PATH.
IS_ISO=false
if findmnt -rno TARGET /iso >/dev/null 2>&1 \
    || findmnt -rno TARGET /nix/.ro-store >/dev/null 2>&1; then
  IS_ISO=true
fi
if [ "$NONINT" != 1 ] && [ "$IS_ISO" = true ] \
    && command -v nixos-install >/dev/null 2>&1; then
  header "Welcome — let's install NixOS"

  # 1. Network (needed later, when nixos-install downloads packages)
  while ! nm-online -q -t 3 2>/dev/null \
      && ! ping -c1 -W2 cache.nixos.org >/dev/null 2>&1; do
    if gum confirm "No internet connection detected. Open the Wi-Fi menu (nmtui)?"; then
      nmtui-connect || true
    else
      note "Continuing offline — installation will need a connection later."
      break
    fi
  done

  # 2. Target disk
  if grep -q ' /mnt ' /proc/mounts; then
    gum confirm "Found a disk already mounted at /mnt — install there?" && INSTALL_MODE=true
  fi
  if [ "$INSTALL_MODE" = false ] && command -v parted >/dev/null 2>&1; then
    if gum confirm "Erase a disk and install NixOS on it? (guided — the disk will be wiped)"; then
      # Never offer the stick we booted from
      BOOT_SRC=$(findmnt -no SOURCE /iso 2>/dev/null || true)
      BOOT_DEV=""
      [ -n "$BOOT_SRC" ] && BOOT_DEV=$(lsblk -no PKNAME "$BOOT_SRC" 2>/dev/null || true)
      CHOICES=()
      while read -r name size model; do
        [ "$name" = "$BOOT_DEV" ] && continue
        CHOICES+=("$name ($size ${model:-disk})")
      done < <(lsblk -dno NAME,SIZE,MODEL,TYPE | awk '$NF=="disk" {NF--; print}')
      if [ "${#CHOICES[@]}" -eq 0 ]; then
        note "No usable disks found."
      else
        PICK=$(pick_one "Install to which disk? (EVERYTHING on it will be erased)" "${CHOICES[@]}")
        TARGET_DISK="/dev/${PICK%% *}"
        CONFIRM=$(gum input --header "This will PERMANENTLY ERASE $TARGET_DISK. Type ERASE to confirm:")
        if [ "$CONFIRM" = "ERASE" ]; then
          case "$TARGET_DISK" in *[0-9]) P="p" ;; *) P="" ;; esac
          DISK_TOUCHED=true
          sudo wipefs -af "$TARGET_DISK" >/dev/null
          if [ -d /sys/firmware/efi ]; then
            sudo parted -s "$TARGET_DISK" -- mklabel gpt \
              mkpart ESP fat32 1MiB 513MiB set 1 esp on \
              mkpart root ext4 513MiB 100%
            sudo udevadm settle
            sudo mkfs.fat -F 32 -n BOOT "$TARGET_DISK${P}1" >/dev/null
            sudo mkfs.ext4 -qF -L nixos "$TARGET_DISK${P}2"
            sudo mount "$TARGET_DISK${P}2" /mnt
            sudo mkdir -p /mnt/boot
            sudo mount "$TARGET_DISK${P}1" /mnt/boot
          else
            sudo parted -s "$TARGET_DISK" -- mklabel gpt \
              mkpart biosboot 1MiB 2MiB set 1 bios_grub on \
              mkpart root ext4 2MiB 100%
            sudo udevadm settle
            sudo mkfs.ext4 -qF -L nixos "$TARGET_DISK${P}2"
            sudo mount "$TARGET_DISK${P}2" /mnt
          fi
          INSTALL_MODE=true
          gum style --foreground 2 "Disk ready and mounted at /mnt."
        else
          note "Not confirmed — no disk was touched."
        fi
      fi
    fi
  fi
  if [ "$INSTALL_MODE" = false ]; then
    note "No install target — generating a config only. Mount a disk at /mnt and re-run to install."
  fi
fi
if [ "$INSTALL_MODE" = false ] && [ "$NONINT" != 1 ] && [ "$IS_ISO" = false ] \
    && command -v nixos-install >/dev/null 2>&1 \
    && grep -q ' /mnt ' /proc/mounts; then
  gum confirm "Found a filesystem mounted at /mnt — set this config up for 'nixos-install' onto it?" && INSTALL_MODE=true
fi
CAPTURE_HW=$INSTALL_MODE

# ── Basics ──────────────────────────────────────────────────────────

[ "$NONINT" != 1 ] && header "Basics"

HOST_DEFAULT="${SE_HOSTNAME:-$(cat /etc/hostname 2>/dev/null || echo "${HOSTNAME:-nixbox}")}"
while :; do
  if [ "$NONINT" = 1 ]; then
    HOSTNAME="$HOST_DEFAULT"
  else
    HOSTNAME=$(gum input --header "Hostname for this machine:" --value "$HOST_DEFAULT")
  fi
  [[ "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && break
  [ "$NONINT" = 1 ] && die "Invalid hostname: $HOSTNAME"
  note "Hostname must be letters, digits, and hyphens (no leading/trailing hyphen)."
done

while :; do
  if [ "$NONINT" = 1 ]; then
    USERNAME="${SE_USERNAME:-user}"
  else
    USERNAME=$(gum input --header "Primary username:" --placeholder "e.g. alice")
  fi
  [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
  [ "$NONINT" = 1 ] && die "Invalid username: $USERNAME"
  note "Username must start with a lowercase letter, then lowercase letters, digits, - or _."
done

# Login password: hashed into the config so the first boot isn't locked out.
PASSWORD_HASH=""
PW="${SE_PASSWORD:-}"
if [ "$NONINT" != 1 ]; then
  while :; do
    PW=$(gum input --password --header "Login password for $USERNAME (leave blank to use 'changeme'):")
    [ -z "$PW" ] && break
    PW2=$(gum input --password --header "Confirm password:")
    [ "$PW" = "$PW2" ] && break
    note "Passwords didn't match — try again, or leave blank to skip."
  done
fi
if [ -n "$PW" ]; then
  if command -v mkpasswd >/dev/null 2>&1; then
    PASSWORD_HASH=$(mkpasswd -m sha-512 -s <<<"$PW")
  else
    note "mkpasswd not available — falling back to initial password 'changeme'."
  fi
fi
unset PW
if [ -n "$PASSWORD_HASH" ]; then
  PASSWORD_NIX="hashedPassword = \"$PASSWORD_HASH\";"
  PW_HINT="the password you chose"
else
  PASSWORD_NIX="initialPassword = \"changeme\"; # CHANGE after first login: run 'passwd'"
  PW_HINT="changeme"
fi

# Timezone / locale / keyboard: default to whatever this machine uses
TZ_DEFAULT="${SE_TIMEZONE:-America/New_York}"
if [ -z "${SE_TIMEZONE:-}" ] && [ -e /etc/localtime ]; then
  TZ_PATH=$(readlink -f /etc/localtime || true)
  case "$TZ_PATH" in
    *zoneinfo/*) TZ_DEFAULT="${TZ_PATH#*zoneinfo/}" ;;
  esac
fi

LOC_DEFAULT="${SE_LOCALE:-${LANG:-en_US.UTF-8}}"
LOC_DEFAULT="${LOC_DEFAULT%%:*}"
case "$LOC_DEFAULT" in C | C.* | POSIX) LOC_DEFAULT="en_US.UTF-8" ;; esac

KB_DEFAULT="${SE_KEYMAP:-}"
if [ -z "$KB_DEFAULT" ] && command -v localectl >/dev/null 2>&1; then
  KB_DEFAULT=$(localectl status 2>/dev/null | sed -n 's/.*X11 Layout: //p' | head -1 || true)
fi
KB_DEFAULT="${KB_DEFAULT:-us}"

if [ "$NONINT" = 1 ]; then
  TIMEZONE="$TZ_DEFAULT"
  LOCALE="$LOC_DEFAULT"
  KB_LAYOUT="$KB_DEFAULT"
else
  TIMEZONE=$(gum input --header "Timezone:" --value "$TZ_DEFAULT")
  LOCALE=$(gum input --header "Locale:" --value "$LOC_DEFAULT")
  KB_LAYOUT=$(gum input --header "Keyboard layout (XKB code, e.g. us, de, fr):" --value "$KB_DEFAULT")
fi
[[ "$LOCALE" =~ ^[A-Za-z0-9_.@-]+$ ]] || die "Invalid locale: $LOCALE"
[[ "$KB_LAYOUT" =~ ^[a-z]+(,[a-z]+)*$ ]] || die "Invalid keyboard layout: $KB_LAYOUT"

OUT_DEFAULT="./nixos-config"
[ "$INSTALL_MODE" = true ] && OUT_DEFAULT="/mnt/etc/nixos"
if [ "$NONINT" = 1 ]; then
  OUTDIR="${SE_OUTDIR:-$OUT_DEFAULT}"
else
  OUTDIR=$(gum input --header "Output directory:" --value "$OUT_DEFAULT")
fi
if [ -d "$OUTDIR" ] && [ -n "$(ls -A "$OUTDIR" 2>/dev/null)" ]; then
  prompt_confirm "$OUTDIR exists and is not empty. Overwrite generated files?" y || {
    note "Aborted — nothing was written."
    exit 0
  }
fi

STATE_VERSION="26.05" # matches the pinned nixpkgs release below

# ── Hardware (auto-detected, confirmed) ─────────────────────────────

[ "$NONINT" != 1 ] && header "Hardware"

# lspci prints hex slots ("01:00.0"); the NixOS PRIME options want
# decimal ("PCI:1:0:0").
pci_to_nix() {
  local slot="$1" bus rest dev fn
  case "$slot" in *:*:*) slot="${slot#*:}" ;; esac # drop a PCI domain
  bus="${slot%%:*}"
  rest="${slot#*:}"
  dev="${rest%%.*}"
  fn="${rest#*.}"
  printf 'PCI:%d:%d:%d\n' "0x$bus" "0x$dev" "0x$fn"
}

# Display controllers: VGA (0300), 3D (0302), display (0380). `lspci
# -mm` quotes its fields, so splitting on the quote gives slot in the
# first field and vendor in the fourth.
NVIDIA_BUSID=""
INTEL_BUSID=""
AMD_BUSID=""
if command -v lspci >/dev/null 2>&1; then
  while read -r slot vendor; do
    [ -n "$slot" ] || continue
    case "$vendor" in
      NVIDIA*)
        [ -n "$NVIDIA_BUSID" ] || NVIDIA_BUSID=$(pci_to_nix "$slot") ;;
      Intel*)
        [ -n "$INTEL_BUSID" ] || INTEL_BUSID=$(pci_to_nix "$slot") ;;
      "Advanced Micro"* | AMD* | ATI*)
        [ -n "$AMD_BUSID" ] || AMD_BUSID=$(pci_to_nix "$slot") ;;
    esac
  done < <( { lspci -mm -d ::0300; lspci -mm -d ::0302; lspci -mm -d ::0380; } 2>/dev/null \
            | awk -F'"' '{ print $1 " " $4 }' )
fi

# Check discrete vendors before Intel so hybrid laptops surface the dGPU
GPU_DETECTED=""
if   [ -n "$NVIDIA_BUSID" ]; then GPU_DETECTED="NVIDIA"
elif [ -n "$AMD_BUSID" ];    then GPU_DETECTED="AMD"
elif [ -n "$INTEL_BUSID" ];  then GPU_DETECTED="Intel"
fi

GPU=""
if [ "$NONINT" = 1 ]; then
  GPU="${SE_GPU:-${GPU_DETECTED:-None / VM}}"
else
  if [ -n "$GPU_DETECTED" ]; then
    gum confirm "Detected GPU: $GPU_DETECTED — use this?" && GPU="$GPU_DETECTED"
  fi
  if [ -z "$GPU" ]; then
    GPU=$(pick_one "GPU vendor:" "AMD" "Intel" "NVIDIA" "None / VM")
  fi
fi

# Handheld gaming PCs identify themselves in DMI. These are the
# product names Handheld Daemon matches, so a hit here corresponds to
# device support on the installed system. ASUS reports the marketing
# name with the model inside it ("ROG Ally X RC72LA_RC72LA_…"); Valve,
# Lenovo, GPD and MSI report the bare model.
DMI_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
DMI_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
HANDHELD_DETECTED=""
case "$DMI_PRODUCT" in
  Jupiter|Galileo)                          HANDHELD_DETECTED="Steam Deck" ;;
  *RC71L*|*RC72LA*|*RC73X*|*RC73Y*)         HANDHELD_DETECTED="ROG Ally" ;;
  83E1|83L3|83N0|83N1|83N6|83Q2|83Q3)       HANDHELD_DETECTED="Legion Go" ;;
  G1617-*|G1618-*)                          HANDHELD_DETECTED="GPD Win" ;;
  MS-1T41|MS-1T42|MS-1T52|MS-1T8K)          HANDHELD_DETECTED="MSI Claw" ;;
  *)
    case "$DMI_VENDOR" in
      AYANEO*|AYADEVICE*|ONE-NETBOOK*|AOKZOE*) HANDHELD_DETECTED="$DMI_VENDOR handheld" ;;
    esac ;;
esac

IS_HANDHELD=false
if [ "$NONINT" = 1 ]; then
  [ "${SE_HANDHELD:-$( [ -n "$HANDHELD_DETECTED" ] && echo 1 || echo 0 )}" = 1 ] && IS_HANDHELD=true
elif [ -n "$HANDHELD_DETECTED" ]; then
  gum confirm "Detected $HANDHELD_DETECTED — set up as a handheld gaming PC?" && IS_HANDHELD=true
fi

# A battery means a laptop. Plain globbing, not compgen: the minimal
# bash this ships with is built without programmable completion, so
# compgen isn't there and the check silently found nothing.
IS_LAPTOP=false
for battery in /sys/class/power_supply/BAT*; do
  if [ -e "$battery" ]; then
    IS_LAPTOP=true
    break
  fi
done

# Handheld Daemon owns TDP profiles and charge limits on a handheld,
# so TLP is offered on laptops only.
USE_TLP=false
if [ "$IS_HANDHELD" = false ]; then
  if [ "$NONINT" = 1 ]; then
    # SE_TLP overrides the battery check either way, so a script that
    # knows what the machine had can say so.
    [ "${SE_TLP:-$( [ "$IS_LAPTOP" = true ] && echo 1 || echo 0 )}" = 1 ] && USE_TLP=true
  elif [ "$IS_LAPTOP" = true ]; then
    gum confirm "Battery detected (laptop) — include TLP power management?" && USE_TLP=true
  fi
fi

# On an installed NixOS system we can capture the real hardware config
if [ "$INSTALL_MODE" = false ] && [ "$NONINT" != 1 ] \
    && command -v nixos-generate-config >/dev/null 2>&1; then
  if gum confirm "Capture THIS machine's hardware config (disks, filesystems)? Choose No if this config is for a different machine."; then
    CAPTURE_HW=true
  fi
fi

# Hybrid graphics: the iGPU drives the panel, the NVIDIA card renders
# on demand. The bus IDs below describe *this* machine, so only offer
# it when this machine is the target — and only on a laptop, since a
# desktop's monitor is normally wired to the discrete card.
IGPU_BUSID=""
IGPU_ATTR=""
if   [ -n "$INTEL_BUSID" ]; then IGPU_BUSID="$INTEL_BUSID"; IGPU_ATTR="intelBusId"
elif [ -n "$AMD_BUSID" ];    then IGPU_BUSID="$AMD_BUSID";  IGPU_ATTR="amdgpuBusId"
fi

USE_PRIME=false
if [ "$GPU" = "NVIDIA" ] && [ -n "$IGPU_BUSID" ] && [ -n "$NVIDIA_BUSID" ]; then
  if [ "$NONINT" = 1 ]; then
    # Opt-in only: these bus IDs describe the machine running the
    # wizard, which non-interactively is not necessarily the target.
    [ "${SE_PRIME:-0}" = 1 ] && USE_PRIME=true
  elif [ "$CAPTURE_HW" = true ] && [ "$IS_LAPTOP" = true ]; then
    gum confirm "Hybrid graphics detected (integrated $IGPU_BUSID + NVIDIA $NVIDIA_BUSID) — set up PRIME offload? (recommended on laptops: the dGPU powers down when idle)" \
      && USE_PRIME=true
  fi
fi

# ── Desktop ─────────────────────────────────────────────────────────

[ "$NONINT" != 1 ] && header "Desktop"

if [ "$NONINT" = 1 ]; then
  DE="${SE_DE:-KDE Plasma}"
else
  DE=$(pick_one "Desktop environment:" \
    "KDE Plasma — familiar Windows-like layout, highly configurable" \
    "GNOME — polished and streamlined, macOS-like workflow" \
    "COSMIC — modern desktop from System76, tiling built in" \
    "Hyprland — keyboard-driven tiling compositor for tinkerers")
fi

# ── Flavors ─────────────────────────────────────────────────────────

case "$DE" in
  "KDE Plasma"*) DE_ATTR="plasma" ;;
  "GNOME"*)      DE_ATTR="gnome" ;;
  "COSMIC"*)     DE_ATTR="cosmic" ;;
  "Hyprland"*)   DE_ATTR="hyprland" ;;
  *)             die "Unknown desktop environment: $DE" ;;
esac

# Gaming and Catppuccin theming are not questions: this is a gaming
# distro, and it has a look. Both are still one line to switch off in
# the generated config.
FLAVOR_TOKENS=""
if [ "$NONINT" = 1 ]; then
  # Two steps, not one: under `set -u` a substitution on an unset
  # SE_FLAVORS aborts the script.
  FLAVOR_TOKENS="${SE_FLAVORS:-}"
  FLAVOR_TOKENS="${FLAVOR_TOKENS//,/ }"
else
  header "Flavors"
  note "Steam, GameMode and Catppuccin theming are included as standard."
  FLAVOR_CHOICES=("development (Docker + libvirt)")
  # KDE Connect comes with the Plasma flavor; asking again would be
  # asking the same question twice.
  [ "$DE_ATTR" != plasma ] && FLAVOR_CHOICES+=("kdeconnect (phone integration)")

  SELECTED=$(pick_many "Optional flavors (space to select, enter to confirm):" \
    "${FLAVOR_CHOICES[@]}")
  has "$SELECTED" "development (Docker + libvirt)" && FLAVOR_TOKENS="$FLAVOR_TOKENS development"
  has "$SELECTED" "kdeconnect (phone integration)" && FLAVOR_TOKENS="$FLAVOR_TOKENS kdeconnect"
fi
want() { case " $FLAVOR_TOKENS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Theming ships with every generated desktop, so its flake input and
# module always go in.
USE_CATPPUCCIN=true

# ── Pre-flight: the module set must be intact ───────────────────────
# The whole tree gets vendored, so a missing category is a broken
# import rather than a missing feature — catch it before writing.

MISSING=()
for d in common desktop network apps gaming development gpu tuning; do
  [ -f "$MODULE_SOURCE/$d/default.nix" ] || MISSING+=("$d/default.nix")
done
[ -f "$MODULE_SOURCE/default.nix" ] || MISSING+=("default.nix")
if [ "${#MISSING[@]}" -gt 0 ]; then
  gum style --foreground 1 "Missing from module source (did you 'git add' new files?):"
  printf '  %s\n' "${MISSING[@]}"
  exit 1
fi

# ── Host facts ──────────────────────────────────────────────────────

case "$(uname -m)" in
  aarch64) SYSTEM="aarch64-linux" ;;
  *)       SYSTEM="x86_64-linux" ;;
esac

# UEFI machines get systemd-boot; legacy BIOS machines get GRUB aimed
# at the target disk (derived from what's mounted at /mnt, or /).
if [ -d /sys/firmware/efi ]; then
  BOOTLOADER_NIX="boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;"
else
  DISK_FOR_GRUB="$TARGET_DISK"
  if [ -z "$DISK_FOR_GRUB" ]; then
    ROOT_SRC=$(findmnt -no SOURCE /mnt 2>/dev/null || findmnt -no SOURCE / 2>/dev/null || true)
    PK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1 || true)
    DISK_FOR_GRUB="/dev/${PK:-sda}"
  fi
  BOOTLOADER_NIX="boot.loader.grub.enable = true;
  boot.loader.grub.device = \"$DISK_FOR_GRUB\"; # legacy BIOS boot"
fi

# Scale the VM test defaults to this machine: half the cores (2–4),
# a quarter of RAM (2–8 GB). Written into vmVariant; user-editable.
VM_CORES=$(( $(nproc) / 2 ))
[ "$VM_CORES" -lt 2 ] && VM_CORES=2
[ "$VM_CORES" -gt 4 ] && VM_CORES=4

VM_MEM=2048
if [ -r /proc/meminfo ]; then
  while read -r key val _; do
    if [ "$key" = "MemTotal:" ]; then
      VM_MEM=$(( val / 1024 / 4 ))
      break
    fi
  done < /proc/meminfo
fi
[ "$VM_MEM" -lt 2048 ] && VM_MEM=2048
[ "$VM_MEM" -gt 8192 ] && VM_MEM=8192

# ── Generate ────────────────────────────────────────────────────────

header "Generating $OUTDIR"
GENERATING=true

ensure_writable_dir "$OUTDIR"

# Owning the directory says nothing about a tree already inside it.
# Writing part of a config over one we can only partly replace would
# leave a mixture of both behind, so the directories we are about to
# write have to be ours before anything is generated.
for sub in flake hosts modules; do
  if [ -e "$OUTDIR/$sub" ] && [ ! -w "$OUTDIR/$sub" ]; then
    die "$OUTDIR/$sub isn't writable by this user. Hand the tree over, then re-run:
  sudo chown -R $(id -u):$(id -g) $OUTDIR"
  fi
done

mkdir -p "$OUTDIR/flake" "$OUTDIR/hosts/$HOSTNAME" "$OUTDIR/modules"

# Vendor the complete module set. Everything is imported; nothing is
# switched on until space-elevator.nix says so — which means turning on
# a feature later never requires fetching anything.
rm -rf "${OUTDIR:?}/modules"
cp -R "$MODULE_SOURCE" "$OUTDIR/modules"
chmod -R u+w "$OUTDIR/modules"

# ── flake.nix ───────────────────────────────────────────────────────

{
  cat <<EOF
{
  description = "NixOS desktop configuration generated by space-elevator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
EOF
  if [ "$USE_CATPPUCCIN" = true ]; then
    cat <<EOF

    catppuccin.url = "github:catppuccin/nix/release-26.05";
EOF
  fi
  cat <<EOF
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./flake/hosts.nix ];
      systems = [ "$SYSTEM" ];
    };
}
EOF
} > "$OUTDIR/flake.nix"

# ── flake/hosts.nix ─────────────────────────────────────────────────

cat <<EOF > "$OUTDIR/flake/hosts.nix"
# flake/hosts.nix — one import per host
{ ... }: {
  imports = [
    ../hosts/$HOSTNAME/$HOSTNAME.nix
  ];
}
EOF

# ── hosts/<name>/<name>.nix ─────────────────────────────────────────

{
  cat <<EOF
# hosts/$HOSTNAME/$HOSTNAME.nix
{ inputs, ... }: {
  flake.nixosConfigurations.$HOSTNAME = inputs.nixpkgs.lib.nixosSystem {
    system = "$SYSTEM";
    specialArgs = { inherit inputs; };
    modules = [

      # ── Features ────────────────────────────────────────
      # The module set declares every feature as an option and
      # turns none of them on by itself; space-elevator.nix is
      # where this machine picks.
      ../../modules
      ./space-elevator.nix
EOF
  if [ "$USE_CATPPUCCIN" = true ]; then
    cat <<EOF

      # Theming lives in its own flake; this is the one feature
      # that needs a module from outside modules/.
      inputs.catppuccin.nixosModules.catppuccin
EOF
  fi
  cat <<EOF

      # ── Host ────────────────────────────────────────────
      ./configuration.nix

    ];
  };
}
EOF
} > "$OUTDIR/hosts/$HOSTNAME/$HOSTNAME.nix"

# ── hosts/<name>/space-elevator.nix ─────────────────────────────────
# The answers, as options. Commented-out lines are deliberate: they
# show what else is available without making anyone read the source.

# Desktop environments: the chosen one on, the rest as comments.
de_lines() {
  local de
  for de in plasma gnome cosmic hyprland; do
    if [ "$de" = "$DE_ATTR" ]; then
      printf '    desktop.%s.enable = true;\n' "$de"
    else
      printf '    # desktop.%s.enable = true;\n' "$de"
    fi
  done
}

gpu_lines() {
  case "$GPU" in
    AMD)
      printf '    gpu.amd.enable = true;\n'
      ;;
    Intel)
      printf '    gpu.intel.enable = true;\n'
      ;;
    NVIDIA)
      if [ "$USE_PRIME" = true ]; then
        cat <<EOF
    gpu.nvidia = {
      enable = true;

      # Hybrid graphics, detected on this machine: the integrated GPU
      # drives the panel and the NVIDIA card renders on demand, then
      # powers down. Run a program on the dGPU with:
      #   nvidia-offload <command>
      prime = {
        enable = true;
        $IGPU_ATTR = "$IGPU_BUSID";
        nvidiaBusId = "$NVIDIA_BUSID";
      };

      # Pre-Turing card (GTX 10xx / 9xx)? The current driver dropped
      # support for those: set driver = "legacy_580"; and remove the
      # prime block's power savings by adding
      # powerManagement.finegrained = false;
    };
EOF
      else
        cat <<'EOF'
    gpu.nvidia.enable = true;
    # Hybrid laptop (integrated GPU + NVIDIA)? Uncomment and fill in
    # the bus IDs from `lspci | grep -E 'VGA|3D'`, converted to
    # decimal — 01:00.0 becomes "PCI:1:0:0":
    #   gpu.nvidia.prime = {
    #     enable = true;
    #     intelBusId  = "PCI:0:2:0";   # or amdgpuBusId on an AMD iGPU
    #     nvidiaBusId = "PCI:1:0:0";
    #   };
    # Pre-Turing card (GTX 10xx / 9xx)?
    #   gpu.nvidia.driver = "legacy_580";
EOF
      fi
      ;;
    *)
      printf '    # No GPU driver selected — the kernel'\''s built-in\n'
      printf '    # drivers handle VMs and basic display output.\n'
      printf '    # gpu.amd.enable = true;\n'
      printf '    # gpu.intel.enable = true;\n'
      printf '    # gpu.nvidia.enable = true;\n'
      ;;
  esac
}

{
  cat <<EOF
# hosts/$HOSTNAME/space-elevator.nix
#
# The feature switches for this machine.
#
# Every module in ../../modules is already imported — these options
# decide which ones do anything. Turning a feature on is one line here
# plus a rebuild; nothing gets downloaded from Space Elevator, because
# the modules are already sitting in this repository.
#
# Each option carries a description in its module, and the commented
# lines below are a tour of what else is on offer.
{ ... }:
{
  spaceElevator = {
    enable = true;
    user.name = "$USERNAME";

    locale = {
      defaultLocale = "$LOCALE";
      keyboardLayout = "$KB_LAYOUT";
    };

    # ── Desktop ─────────────────────────────────────────────
    # One at a time. Switching is: change the line, rebuild, log
    # out and back in. The shared plumbing — audio, Bluetooth,
    # printing, fonts, removable media, the common app set —
    # follows whichever one you pick.
EOF
  de_lines
  echo
  cat <<'EOF'
    # Catppuccin, system-wide — standard on every Space Elevator
    # desktop. Flavors: latte (light), frappe, macchiato, mocha
    # (darkest). Accents: mauve, blue, teal, peach, red and more.
    desktop.theming = {
      enable = true;
      flavor = "mocha";
      accent = "mauve";
    };

    # Firefox comes with the common app set. Prefer a different
    # browser? Turn it off and install yours in configuration.nix:
    #   desktop.packages.firefox = false;
EOF
  echo
  if want kdeconnect; then
    printf '    desktop.kdeconnect.enable = true;\n'
  elif [ "$DE_ATTR" = plasma ]; then
    printf '    # KDE Connect comes with Plasma; switch it off with:\n'
    printf '    # desktop.kdeconnect.enable = false;\n'
  else
    printf '    # Phone integration (notifications, file transfer):\n'
    printf '    # desktop.kdeconnect.enable = true;\n'
  fi

  cat <<EOF

    # ── Hardware ────────────────────────────────────────────
EOF
  gpu_lines
  echo
  if [ "$USE_TLP" = true ]; then
    cat <<'EOF'
    # Laptop power management. It replaces the desktop's own power
    # profile switcher, and holds the battery between 40% and 80%
    # to spare it — set chargeThresholds = null; to charge fully.
    tuning.tlp.enable = true;
EOF
  elif [ "$IS_HANDHELD" = true ]; then
    cat <<EOF
    # Handheld gaming PC${HANDHELD_DETECTED:+ ($HANDHELD_DETECTED)}.
    # TDP profiles and charge limits belong to Handheld Daemon,
    # so TLP stays off:
    # tuning.tlp.enable = true;
EOF
  else
    cat <<'EOF'
    # Laptop power management (conflicts with the desktop's own
    # power profile switcher, so it is off on desktops):
    # tuning.tlp.enable = true;
EOF
  fi

  if [ "$GPU" = NVIDIA ]; then
    cat <<'EOF'

    # Kernel. "default" here because the NVIDIA driver asks for it:
    # mainline periodically outruns driver support and the build
    # breaks. "latest", "zen" or "xanmod" override that — zen and
    # xanmod are tuned for desktop latency, and you will be warned
    # that the pairing is the fragile one.
    #   base.kernel = "zen";
EOF
  else
    cat <<'EOF'

    # Kernel: "latest" (the default), "default" (the release's own,
    # oldest and steadiest), or "zen" / "xanmod" — mainline patched
    # for desktop latency under load, which is what you feel in a
    # game while something else is running.
    #   base.kernel = "zen";
EOF
  fi

  cat <<'EOF'

    # ── Gaming ──────────────────────────────────────────────
    # Standard equipment: Steam (Proton-GE, gamescope, protontricks),
    # GameMode, MangoHud with GOverlay, the non-Steam launchers
    # (Heroic, Lutris, ProtonUp-Qt), controller drivers for Xbox,
    # PlayStation, Switch and 8BitDo pads, and the kernel tunables
    # games need.
    # Not a gaming machine after all? gaming.enable = false;
    gaming.enable = true;
EOF
  if [ "$IS_HANDHELD" = true ]; then
    cat <<'EOF'

    # Adds the SteamOS-style Big Picture session to the login screen.
    gaming.steam.gamescopeSession = true;

    # There when you want them:
EOF
  else
    cat <<'EOF'

    # There when you want them:
    #   gaming.steam.gamescopeSession = true;  # SteamOS-style Big Picture session at login
EOF
  fi
  cat <<'EOF'
    #   gaming.streaming.enable = true;        # Sunshine — stream to a Moonlight client
    #   gaming.rgb.enable = true;              # OpenRGB lighting control
    #   gaming.controllers.mice = true;        # Piper, for configuring gaming mice
    #
    # Individual pieces, if you want some but not all:
    #   gaming.steam.protonGE = false;
    #   gaming.steam.openFirewall = false;     # no Remote Play
    #   gaming.gamemode.mangohud = false;
    #   gaming.launchers.lutris = false;

    # ── Flavors ─────────────────────────────────────────────
EOF
  if want development; then
    printf '    development.enable = true;   # Docker + libvirt/virt-manager\n'
  else
    printf '    # development.enable = true;   # Docker + libvirt/virt-manager\n'
  fi

  cat <<'EOF'

    # ── Housekeeping ────────────────────────────────────────
    # On by default: zram swap, earlyoom, weekly garbage
    # collection, Nix tooling (nh, nvd, nix-tree). Turn one off
    # individually, or the lot of them with tuning.enable = false;
    #
    #   tuning.nixGc.keepDays = 30;
    #   tuning.zram.memoryPercent = 25;
    #   network.firewall.allowedTCPPorts = [ 8080 ];
  };
}
EOF
} > "$OUTDIR/hosts/$HOSTNAME/space-elevator.nix"

# ── hosts/<name>/configuration.nix ──────────────────────────────────

cat <<EOF > "$OUTDIR/hosts/$HOSTNAME/configuration.nix"
# hosts/$HOSTNAME/configuration.nix
{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader (matched to this machine's firmware by the wizard)
  $BOOTLOADER_NIX

  networking.hostName = "$HOSTNAME";
  time.timeZone = "$TIMEZONE";

  users.users.$USERNAME = {
    isNormalUser = true;
    description = "$USERNAME";
    extraGroups = [ "wheel" "networkmanager" ];
    $PASSWORD_NIX
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
  ];

  # VM test settings — applied ONLY by \`nixos-rebuild build-vm\`,
  # ignored entirely on a real installation. Sized from the machine
  # that generated this config; adjust freely.
  virtualisation.vmVariant = {
    virtualisation.memorySize = $VM_MEM;
    virtualisation.cores = $VM_CORES;
    virtualisation.diskSize = 8192; # MB — room to actually try things
  };

  system.stateVersion = "$STATE_VERSION"; # do not change after install
}
EOF

# ── hosts/<name>/hardware-configuration.nix ─────────────────────────

HW_CAPTURED=false
if [ "$CAPTURE_HW" = true ]; then
  ROOT_ARGS=()
  [ "$INSTALL_MODE" = true ] && ROOT_ARGS=(--root /mnt)
  HW_TEXT=$(nixos-generate-config "${ROOT_ARGS[@]}" --show-hardware-config 2>/dev/null) \
    || HW_TEXT=$(sudo -n nixos-generate-config "${ROOT_ARGS[@]}" --show-hardware-config 2>/dev/null) \
    || HW_TEXT=""
  if [ -n "$HW_TEXT" ]; then
    printf '%s\n' "$HW_TEXT" > "$OUTDIR/hosts/$HOSTNAME/hardware-configuration.nix"
    HW_CAPTURED=true
  else
    note "nixos-generate-config failed (it may need sudo) — writing placeholder instead."
  fi
fi

if [ "$HW_CAPTURED" = false ]; then
  cat <<EOF > "$OUTDIR/hosts/$HOSTNAME/hardware-configuration.nix"
# PLACEHOLDER — replace before installing on real hardware:
#   nixos-generate-config --show-hardware-config > hosts/$HOSTNAME/hardware-configuration.nix
# This stub is sufficient for VM testing (nixos-rebuild build-vm);
# a real install will refuse to build until it is replaced.
{ }
EOF
fi

# ── update.sh ───────────────────────────────────────────────────────

cat <<EOF > "$OUTDIR/update.sh"
#!/usr/bin/env bash
# Update all inputs and switch to the new system.
# If anything breaks afterwards, reboot and choose the previous
# generation in the boot menu — that rolls the whole system back.
set -euo pipefail
cd "\$(dirname "\$0")"
nix flake update
nixos-rebuild switch --sudo --flake .#$HOSTNAME
EOF
chmod +x "$OUTDIR/update.sh"

# ── README ──────────────────────────────────────────────────────────
# Quoted heredocs (no expansion — the code fences make that unsafe),
# with placeholders substituted afterwards, assembled in chunks.

subst() {
  sed -e "s|@HOSTNAME@|$HOSTNAME|g" \
      -e "s|@USERNAME@|$USERNAME|g" \
      -e "s|@PW_HINT@|$PW_HINT|g"
}

{
subst <<'EOF'
# @HOSTNAME@ NixOS desktop

Generated by space-elevator. Structure:

- flake.nix — inputs and flake-parts entry
- flake/hosts.nix — registers each host
- hosts/@HOSTNAME@/space-elevator.nix — **the feature switches for this
  machine**: what's on, what's available, all in one file
- hosts/@HOSTNAME@/configuration.nix — user, bootloader, packages
- modules/ — every feature, as options. All of them are imported;
  space-elevator.nix decides which ones do anything
- update.sh — update everything and switch

## What's already on

**Gaming** — Steam (Proton-GE, gamescope, protontricks), Heroic, Lutris
and ProtonUp-Qt for the games that aren't on Steam, GameMode, MangoHud
with GOverlay, and controller support for Xbox, PlayStation, Switch and
8BitDo pads.

**The desktop** — Firefox, Vesktop, the common app set, Catppuccin
theming, and the plumbing: audio, Bluetooth, printing, fonts,
automounting, Flatpak wired to Flathub.

**Housekeeping** — zram, earlyoom, weekly garbage collection, and the
Nix tooling worth having (`nh`, `nvd`, `nix-tree`).

A few things wait for you to ask: a SteamOS-style Big Picture session,
Sunshine game streaming, OpenRGB, Piper, and a performance kernel. Each
is one commented line in the file below.

## Turning features on and off

Open `hosts/@HOSTNAME@/space-elevator.nix`. Every feature is one line:

```nix
spaceElevator = {
  development.enable = true;         # Docker + libvirt
  desktop.theming.flavor = "latte";  # light theme instead
  desktop.bluetooth.enable = false;  # don't need it
  gaming.enable = false;             # not a gaming machine after all
};
```

Then `./update.sh` (or `sudo nixos-rebuild switch --flake .#@HOSTNAME@`).
Nothing is downloaded from Space Elevator to enable a feature — every
module is already in `modules/`, waiting to be switched on. Each option
has a description in its module explaining what it does.

## Test drive in a VM (no installation needed)

```
git init && git add -A   # flakes only see tracked files
nixos-rebuild build-vm --flake .#@HOSTNAME@
./result/bin/run-@HOSTNAME@-vm
```

Log in as @USERNAME@ with @PW_HINT@. Delete @HOSTNAME@.qcow2 for a
factory-fresh boot.

## Installing on real hardware

EOF
if [ "$INSTALL_MODE" = true ]; then
  subst <<'EOF'
This config was generated in the installer with your mounted system at
/mnt, and the hardware configuration was captured from it. To install:

1. `git init && git add -A` (flakes only see tracked files)
2. `sudo nixos-install --flake .#@HOSTNAME@`
3. Set the root password when prompted, then reboot.
EOF
elif [ "$HW_CAPTURED" = true ]; then
  subst <<'EOF'
hardware-configuration.nix was captured from the machine that generated
this config. Installing on a *different* machine? Regenerate it there:

```
nixos-generate-config --show-hardware-config > hosts/@HOSTNAME@/hardware-configuration.nix
```

Then:

1. `git init && git add -A` (flakes only see tracked files)
2. `sudo nixos-rebuild switch --flake .#@HOSTNAME@`
EOF
else
  subst <<'EOF'
1. Replace the placeholder hardware config on the target machine:
   ```
   nixos-generate-config --show-hardware-config > hosts/@HOSTNAME@/hardware-configuration.nix
   ```
2. `git init && git add -A` (flakes only see tracked files)
3. `sudo nixos-rebuild switch --flake .#@HOSTNAME@`
EOF
fi
subst <<'EOF'

## Installing apps

Open your desktop's app store (Discover, GNOME Software, or COSMIC
Store) to install applications from Flathub with a click — no
configuration editing needed. System-level packages live in
hosts/@HOSTNAME@/configuration.nix under environment.systemPackages.

## Updating

Run `./update.sh`. It updates every input and switches to the new
system. **If an update ever breaks something, reboot and pick the
previous entry in the boot menu** — NixOS keeps old generations
around, so rolling back is always one reboot away.

## Adding another host

Copy hosts/@HOSTNAME@ to hosts/<newname>, rename @HOSTNAME@.nix, adjust
the switches in its space-elevator.nix, and add one line to
flake/hosts.nix. Hosts share the same modules/ directory, so a second
machine can enable a completely different set of features.
EOF
} > "$OUTDIR/README.md"

# ── Done ────────────────────────────────────────────────────────────

if [ "$INSTALL_MODE" = true ]; then
  INSTALL_HINT="  sudo nixos-install --flake .#$HOSTNAME   (then set root password and reboot)"
elif [ "$HW_CAPTURED" = true ]; then
  INSTALL_HINT="  sudo nixos-rebuild switch --flake .#$HOSTNAME   (hardware config already captured)"
else
  INSTALL_HINT="  1. nixos-generate-config --show-hardware-config > hosts/$HOSTNAME/hardware-configuration.nix
  2. sudo nixos-rebuild switch --flake .#$HOSTNAME"
fi

COUNT=$(find "$OUTDIR/modules" -name '*.nix' ! -name default.nix | wc -l)
gum style \
  --border rounded --border-foreground 2 \
  --padding "1 2" --margin "1 0" \
  "Liftoff! Generated $OUTDIR with $COUNT features available." \
  "Switch any of them on in hosts/$HOSTNAME/space-elevator.nix." \
  "" \
  "Test drive it in a VM right now:" \
  "  cd $OUTDIR && git init && git add -A" \
  "  nixos-rebuild build-vm --flake .#$HOSTNAME" \
  "  ./result/bin/run-$HOSTNAME-vm    (login: $USERNAME / $PW_HINT)" \
  "" \
  "Install on real hardware:" \
  "$INSTALL_HINT"

if [ "$INSTALL_MODE" = true ] && command -v nix >/dev/null 2>&1; then
  note "Preparing the package index (downloads the nixpkgs snapshot)..."
  LOCK_ARGS=()
  [ -n "$SE_NIXPKGS_REV" ] && LOCK_ARGS=(--override-input nixpkgs "github:NixOS/nixpkgs/$SE_NIXPKGS_REV")
  lock_flake() { (cd "$OUTDIR" && nix flake lock "${LOCK_ARGS[@]}"); }
  if ! lock_flake; then
    note "Download hiccup — clearing the fetch cache and retrying..."
    rm -rf "$HOME/.cache/nix"
    lock_flake
  fi
fi

if prompt_confirm "Initialize a git repository in $OUTDIR now? (flakes require tracked files)" y; then
  git -C "$OUTDIR" init -q
  git -C "$OUTDIR" add -A
  gum style --foreground 2 "Git repo initialized and files staged."
fi

if [ "$INSTALL_MODE" = true ]; then
  if gum confirm "Begin the installation now? (downloads and installs your desktop — 10 to 30 minutes)"; then
    # --no-root-passwd: root stays locked; your user has sudo via wheel
    if sudo nixos-install --flake "$OUTDIR#$HOSTNAME" --no-root-passwd; then
      gum style \
        --border double --border-foreground 2 \
        --padding "1 3" --margin "1 0" --align center \
        "🚀 Installation complete!" \
        "" \
        "Remove the USB stick when the screen goes dark."
      if gum confirm "Reboot into your new desktop now?"; then
        sudo reboot
      fi
    else
      gum style --foreground 1 "nixos-install reported an error — scroll up for details. Your config is safe at $OUTDIR; fix and re-run: sudo nixos-install --flake $OUTDIR#$HOSTNAME --no-root-passwd"
    fi
  else
    note "When ready: sudo nixos-install --flake $OUTDIR#$HOSTNAME --no-root-passwd"
  fi
fi
