#!/usr/bin/env bash
# space-elevator — opinionated NixOS desktop generator
# Answer a few questions, get a complete desktop flake with distro-grade defaults.
#
# Non-interactive mode (for CI / scripting): set SE_NONINTERACTIVE=1 and any of
#   SE_HOSTNAME SE_USERNAME SE_PASSWORD SE_TIMEZONE SE_LOCALE SE_KEYMAP
#   SE_OUTDIR SE_GPU (AMD|Intel|NVIDIA|None) SE_DE ("KDE Plasma"|GNOME|COSMIC|Hyprland)
#   SE_FLAVORS (comma list of: gaming,development,theming,kdeconnect)
#
# MODULE_SOURCE is injected by flake.nix; the fallback covers standalone dev runs.
set -euo pipefail
MODULE_SOURCE="${MODULE_SOURCE:-$(cd "$(dirname "$0")" && pwd)/modules}"
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
on_err() {
  echo
  if [ "$GENERATING" = true ]; then
    gum style --foreground 1 "Generation failed — $OUTDIR may be incomplete."
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

if [ "$NONINT" = 1 ]; then
  OUTDIR="${SE_OUTDIR:-./nixos-config}"
else
  OUTDIR=$(gum input --header "Output directory:" --value "./nixos-config")
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

GPU_DETECTED=""
if command -v lspci >/dev/null 2>&1; then
  # VGA (0300), 3D (0302), and display (0380) controllers
  PCI=$( { lspci -mm -d ::0300; lspci -mm -d ::0302; lspci -mm -d ::0380; } 2>/dev/null || true)
  # Check discrete vendors before Intel so hybrid laptops surface the dGPU
  case "$PCI" in
    *NVIDIA*)                           GPU_DETECTED="NVIDIA" ;;
    *"Advanced Micro"* | *AMD* | *ATI*) GPU_DETECTED="AMD" ;;
    *Intel*)                            GPU_DETECTED="Intel" ;;
  esac
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

USE_TLP=false
if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then
  if [ "$NONINT" = 1 ]; then
    USE_TLP=true
  else
    gum confirm "Battery detected (laptop) — include TLP power management?" && USE_TLP=true
  fi
fi

# Installer ISO detection: nixos-install available and a target mounted at /mnt
INSTALL_MODE=false
CAPTURE_HW=false
if [ "$NONINT" != 1 ] && command -v nixos-install >/dev/null 2>&1 \
    && grep -q ' /mnt ' /proc/mounts; then
  if gum confirm "Installer environment detected (target mounted at /mnt). Set this config up for 'nixos-install'?"; then
    INSTALL_MODE=true
    CAPTURE_HW=true
  fi
fi

# On an installed NixOS system we can capture the real hardware config
if [ "$INSTALL_MODE" = false ] && [ "$NONINT" != 1 ] \
    && command -v nixos-generate-config >/dev/null 2>&1; then
  if gum confirm "Capture THIS machine's hardware config (disks, filesystems)? Choose No if this config is for a different machine."; then
    CAPTURE_HW=true
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

FLAVOR_TOKENS=""
if [ "$NONINT" = 1 ]; then
  FLAVOR_TOKENS="${SE_FLAVORS//,/ }"
else
  header "Flavors"
  SELECTED=$(pick_many "Optional flavors (space to select, enter to confirm):" \
    "gaming (Steam + gamemode)" \
    "development (Docker + libvirt)" \
    "theming (Catppuccin)" \
    "kdeconnect (phone integration)")
  has "$SELECTED" "gaming (Steam + gamemode)"      && FLAVOR_TOKENS="$FLAVOR_TOKENS gaming"
  has "$SELECTED" "development (Docker + libvirt)" && FLAVOR_TOKENS="$FLAVOR_TOKENS development"
  has "$SELECTED" "theming (Catppuccin)"           && FLAVOR_TOKENS="$FLAVOR_TOKENS theming"
  has "$SELECTED" "kdeconnect (phone integration)" && FLAVOR_TOKENS="$FLAVOR_TOKENS kdeconnect"
fi
want() { case " $FLAVOR_TOKENS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ── Build module list ───────────────────────────────────────────────
# The baseline is unconditional: this is the "distro" layer every
# generated desktop gets. Everything below it is driven by answers.

MODULES=(
  common/base.nix
  common/base-locale.nix
  desktop/audio.nix
  desktop/bluetooth.nix
  desktop/printing.nix
  desktop/nerdfonts.nix
  desktop/desktop-packages.nix
  network/networkmanager.nix
  network/firewall.nix
  apps/flatpak.nix
  tuning/nix-gc.nix
  tuning/nix-tools.nix
  tuning/zram.nix
  tuning/gvfs.nix
  tuning/earlyoom.nix
)

case "$GPU" in
  AMD)    MODULES+=("gpu/amdgpu.nix") ;;
  Intel)  MODULES+=("gpu/intel-gpu.nix") ;;
  NVIDIA) MODULES+=("gpu/nvidia.nix") ;;
esac

case "$DE" in
  "KDE Plasma"*) MODULES+=("desktop/plasma.nix") ;;
  "GNOME"*)      MODULES+=("desktop/gnome.nix") ;;
  "COSMIC"*)     MODULES+=("desktop/cosmic.nix") ;;
  "Hyprland"*)   MODULES+=("desktop/hyprland.nix") ;;
  *)             die "Unknown desktop environment: $DE" ;;
esac

[ "$USE_TLP" = true ] && MODULES+=("tuning/tlp.nix")

USE_CATPPUCCIN=false
want gaming      && MODULES+=("gaming/steam.nix" "gaming/gamemode.nix")
want development && MODULES+=("apps/docker.nix" "apps/virtualisation.nix")
want kdeconnect  && MODULES+=("desktop/kdeconnect.nix")
if want theming; then
  MODULES+=("desktop/theming.nix")
  USE_CATPPUCCIN=true
fi

# ── Pre-flight: verify all selected modules exist ───────────────────

MISSING=()
for m in "${MODULES[@]}"; do
  [ -f "$MODULE_SOURCE/$m" ] || MISSING+=("$m")
done
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

mkdir -p "$OUTDIR/flake" "$OUTDIR/hosts/$HOSTNAME" "$OUTDIR/modules"

# Copy selected modules
for m in "${MODULES[@]}"; do
  dest="$OUTDIR/modules/$m"
  mkdir -p "$(dirname "$dest")"
  cp "$MODULE_SOURCE/$m" "$dest"
  chmod u+w "$dest"
done

# Remove any category directories that ended up empty
find "$OUTDIR/modules" -type d -empty -delete

# Substitute placeholders in any module that carries them
{ grep -rlE '@(USERNAME|LOCALE|KB_LAYOUT)@' "$OUTDIR/modules" 2>/dev/null || true; } | while read -r f; do
  sed -i \
    -e "s|@USERNAME@|$USERNAME|g" \
    -e "s|@LOCALE@|$LOCALE|g" \
    -e "s|@KB_LAYOUT@|$KB_LAYOUT|g" \
    "$f"
done

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

      # ── Host ────────────────────────────────────────────
      ./configuration.nix

      # ── Modules ─────────────────────────────────────────
EOF
  for m in "${MODULES[@]}"; do
    printf '      ../../modules/%s\n' "$m"
  done
  cat <<EOF

    ];
  };
}
EOF
} > "$OUTDIR/hosts/$HOSTNAME/$HOSTNAME.nix"

# ── hosts/<name>/configuration.nix ──────────────────────────────────

cat <<EOF > "$OUTDIR/hosts/$HOSTNAME/configuration.nix"
# hosts/$HOSTNAME/configuration.nix
{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader (UEFI). For legacy BIOS use boot.loader.grub instead.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
  };

  system.stateVersion = "$STATE_VERSION"; # do not change after install
}
EOF

# ── hosts/<name>/hardware-configuration.nix ─────────────────────────

HW_CAPTURED=false
if [ "$CAPTURE_HW" = true ]; then
  ROOT_ARGS=()
  [ "$INSTALL_MODE" = true ] && ROOT_ARGS=(--root /mnt)
  if nixos-generate-config "${ROOT_ARGS[@]}" --show-hardware-config \
      > "$OUTDIR/hosts/$HOSTNAME/hardware-configuration.nix" 2>/dev/null; then
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
sudo nixos-rebuild switch --flake .#$HOSTNAME
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
- hosts/@HOSTNAME@/ — per-machine config
- modules/ — feature modules (importing a file enables it; delete the
  import line in hosts/@HOSTNAME@/@HOSTNAME@.nix to disable one)
- update.sh — update everything and switch

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

Copy hosts/@HOSTNAME@ to hosts/<newname>, rename the files, adjust the
module list, and add one line to flake/hosts.nix.
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

COUNT="${#MODULES[@]}"
gum style \
  --border rounded --border-foreground 2 \
  --padding "1 2" --margin "1 0" \
  "Liftoff! Generated $OUTDIR with $COUNT modules." \
  "" \
  "Test drive it in a VM right now:" \
  "  cd $OUTDIR && git init && git add -A" \
  "  nixos-rebuild build-vm --flake .#$HOSTNAME" \
  "  ./result/bin/run-$HOSTNAME-vm    (login: $USERNAME / $PW_HINT)" \
  "" \
  "Install on real hardware:" \
  "$INSTALL_HINT"

if prompt_confirm "Initialize a git repository in $OUTDIR now? (flakes require tracked files)" y; then
  git -C "$OUTDIR" init -q
  git -C "$OUTDIR" add -A
  gum style --foreground 2 "Git repo initialized and files staged."
fi
