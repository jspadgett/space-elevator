#!/usr/bin/env bash
# space-elevator — interactive NixOS flake generator
# MODULE_SOURCE is injected by flake.nix and points to the vendored modules/ dir.

# ── Helpers ─────────────────────────────────────────────────────────

header() {
  gum style --border rounded --border-foreground 6 --padding "0 2" --margin "1 0" "$1"
}

# gum choose exits nonzero on ESC/empty; treat as "nothing selected"
pick_many() {
  gum choose --no-limit --header "$1" "${@:2}" || true
}

pick_one() {
  gum choose --header "$1" "${@:2}"
}

echo ""
gum style \
  --border double --border-foreground 6 \
  --padding "1 3" --margin "0 2" --align center \
  "🚀 SPACE ELEVATOR" \
  "" \
  "From bare metal to orbit: answer a few" \
  "questions, get a complete NixOS flake."

# ── Basics ──────────────────────────────────────────────────────────

header "Basics"

HOSTNAME=$(gum input --header "Hostname for this machine:" --placeholder "e.g. nixbox")
[ -z "$HOSTNAME" ] && { echo "Hostname is required."; exit 1; }

USERNAME=$(gum input --header "Primary username:" --placeholder "e.g. admin, user")
[ -z "$USERNAME" ] && { echo "Username is required."; exit 1; }

TIMEZONE=$(gum input --header "Timezone:" --placeholder "e.g. America/New_York" --value "America/New_York")

STATE_VERSION=$(gum input --header "NixOS state version:" --value "25.11")

OUTDIR=$(gum input --header "Output directory:" --value "./nixos-config")

# ── Hardware ────────────────────────────────────────────────────────

header "Hardware"

GPU=$(pick_one "GPU vendor:" "AMD" "Intel" "NVIDIA" "None / VM")

# ── Desktop ─────────────────────────────────────────────────────────

header "Desktop"

DE=$(pick_one "Desktop environment:" "KDE Plasma" "Hyprland" "COSMIC" "GNOME" "Headless (no desktop)")

DESKTOP_EXTRAS=""
if [ "$DE" != "Headless (no desktop)" ]; then
  DESKTOP_EXTRAS=$(pick_many "Desktop extras (space to select, enter to confirm):" \
    "bluetooth" "printing" "nerdfonts" "desktop-packages" "theming (Catppuccin)" "kdeconnect")
fi

# ── Features ────────────────────────────────────────────────────────

header "Features"

NETWORK_SEL=$(pick_many "Networking:" \
  "networkmanager" "tailscale" "mullvad" "ssh-hardened" "fail2ban" "mtr")

GAMING_SEL=""
if [ "$DE" != "Headless (no desktop)" ]; then
  GAMING_SEL=$(pick_many "Gaming:" "steam" "gamemode")
fi

APPS_SEL=$(pick_many "Apps & runtimes:" \
  "flatpak" "appimage" "signal" "virtualisation (libvirt)" "docker")

TUNING_SEL=$(pick_many "System tuning & maintenance:" \
  "nix-gc" "nix-tools" "zram" "swapfile" "earlyoom" "ssd" "firewall" \
  "auto-upgrade" "tlp (laptop)" "shell-zsh" "gpgagent" "gvfs" "syncthing")

# ── Options ─────────────────────────────────────────────────────────

header "Options"

USE_HM=false
gum confirm "Include home-manager (per-user dotfile management)?" && USE_HM=true

USE_AGENIX=false
gum confirm "Include agenix (encrypted secrets)?" && USE_AGENIX=true

USE_CATPPUCCIN=false
case "$DESKTOP_EXTRAS" in *theming*) USE_CATPPUCCIN=true ;; esac

# ── Build selection list ────────────────────────────────────────────
# Each entry: "relative/module/path.nix"

MODULES=()
MODULES+=("common/base.nix" "common/base-locale.nix")

case "$GPU" in
  AMD)    MODULES+=("gpu/amdgpu.nix") ;;
  Intel)  MODULES+=("gpu/intel-gpu.nix") ;;
  NVIDIA) MODULES+=("gpu/nvidia.nix") ;;
esac

case "$DE" in
  "KDE Plasma") MODULES+=("desktop/plasma.nix" "desktop/audio.nix") ;;
  "Hyprland")   MODULES+=("desktop/hyprland.nix" "desktop/audio.nix") ;;
  "COSMIC")     MODULES+=("desktop/cosmic.nix" "desktop/audio.nix") ;;
  "GNOME")      MODULES+=("desktop/gnome.nix" "desktop/audio.nix") ;;
esac

add_if() { # add_if <selection-var> <needle> <module-path>
  case "$1" in *"$2"*) MODULES+=("$3") ;; esac
}

add_if "$DESKTOP_EXTRAS" "bluetooth"        "desktop/bluetooth.nix"
add_if "$DESKTOP_EXTRAS" "printing"         "desktop/printing.nix"
add_if "$DESKTOP_EXTRAS" "nerdfonts"        "desktop/nerdfonts.nix"
add_if "$DESKTOP_EXTRAS" "desktop-packages" "desktop/desktop-packages.nix"
add_if "$DESKTOP_EXTRAS" "theming"          "desktop/theming.nix"
add_if "$DESKTOP_EXTRAS" "kdeconnect"       "desktop/kdeconnect.nix"

add_if "$NETWORK_SEL" "networkmanager" "network/networkmanager.nix"
add_if "$NETWORK_SEL" "tailscale"      "network/tailscale.nix"
add_if "$NETWORK_SEL" "mullvad"        "network/mullvad.nix"
add_if "$NETWORK_SEL" "ssh-hardened"   "network/ssh-hardened.nix"
add_if "$NETWORK_SEL" "fail2ban"       "network/fail2ban.nix"
add_if "$NETWORK_SEL" "mtr"            "network/mtr.nix"

add_if "$GAMING_SEL" "steam"    "gaming/steam.nix"
add_if "$GAMING_SEL" "gamemode" "gaming/gamemode.nix"

add_if "$APPS_SEL" "flatpak"        "apps/flatpak.nix"
add_if "$APPS_SEL" "appimage"       "apps/appimage.nix"
add_if "$APPS_SEL" "signal"         "apps/signal.nix"
add_if "$APPS_SEL" "virtualisation" "apps/virtualisation.nix"
add_if "$APPS_SEL" "docker"         "apps/docker.nix"

add_if "$TUNING_SEL" "nix-gc"       "tuning/nix-gc.nix"
add_if "$TUNING_SEL" "nix-tools"    "tuning/nix-tools.nix"
add_if "$TUNING_SEL" "zram"         "tuning/zram.nix"
add_if "$TUNING_SEL" "swapfile"     "tuning/swapfile.nix"
add_if "$TUNING_SEL" "earlyoom"     "tuning/earlyoom.nix"
add_if "$TUNING_SEL" "ssd"          "tuning/ssd.nix"
add_if "$TUNING_SEL" "firewall"     "network/firewall.nix"
add_if "$TUNING_SEL" "auto-upgrade" "tuning/auto-upgrade.nix"
add_if "$TUNING_SEL" "tlp"          "tuning/tlp.nix"
add_if "$TUNING_SEL" "shell-zsh"    "tuning/shell-zsh.nix"
add_if "$TUNING_SEL" "gpgagent"     "tuning/gpgagent.nix"
add_if "$TUNING_SEL" "gvfs"         "tuning/gvfs.nix"
add_if "$TUNING_SEL" "syncthing"    "tuning/syncthing.nix"

if [ "$USE_AGENIX" = true ]; then
  MODULES+=("common/base-agenix.nix")
fi

# Sanity warnings (non-fatal)
case "$NETWORK_SEL" in
  *fail2ban*)
    case "$NETWORK_SEL" in
      *ssh-hardened*) : ;;
      *) gum style --foreground 3 "Note: fail2ban selected without ssh-hardened; it mainly guards SSH." ;;
    esac ;;
esac

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

# ── VM sizing ───────────────────────────────────────────────────────
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

# Substitute username placeholders (syncthing)
if [ -f "$OUTDIR/modules/tuning/syncthing.nix" ]; then
  sed -i "s/@USERNAME@/$USERNAME/g" "$OUTDIR/modules/tuning/syncthing.nix"
fi

# ── flake.nix ───────────────────────────────────────────────────────

{
  echo '{'
  echo '  description = "NixOS configuration generated by space-elevator";'
  echo ''
  echo '  inputs = {'
  echo '    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";'
  echo '    flake-parts.url = "github:hercules-ci/flake-parts";'
  if [ "$USE_HM" = true ]; then
    echo ''
    echo '    home-manager = {'
    echo '      url = "github:nix-community/home-manager/release-25.11";'
    echo '      inputs.nixpkgs.follows = "nixpkgs";'
    echo '    };'
  fi
  if [ "$USE_AGENIX" = true ]; then
    echo ''
    echo '    agenix = {'
    echo '      url = "github:ryantm/agenix";'
    echo '      inputs.nixpkgs.follows = "nixpkgs";'
    echo '    };'
  fi
  if [ "$USE_CATPPUCCIN" = true ]; then
    echo ''
    echo '    catppuccin.url = "github:catppuccin/nix/release-25.11";'
  fi
  echo '  };'
  echo ''
  echo '  outputs = inputs@{ flake-parts, ... }:'
  echo '    flake-parts.lib.mkFlake { inherit inputs; } {'
  echo '      imports = [ ./flake/hosts.nix ];'
  echo '      systems = [ "x86_64-linux" ];'
  echo '    };'
  echo '}'
} > "$OUTDIR/flake.nix"

# ── flake/hosts.nix ─────────────────────────────────────────────────

{
  echo '# flake/hosts.nix — one import per host'
  echo '{ ... }: {'
  echo '  imports = ['
  echo "    ../hosts/$HOSTNAME/$HOSTNAME.nix"
  echo '  ];'
  echo '}'
} > "$OUTDIR/flake/hosts.nix"

# ── hosts/<name>/<name>.nix ─────────────────────────────────────────

{
  echo "# hosts/$HOSTNAME/$HOSTNAME.nix"
  echo '{ inputs, ... }: {'
  echo "  flake.nixosConfigurations.$HOSTNAME = inputs.nixpkgs.lib.nixosSystem {"
  echo '    system = "x86_64-linux";'
  echo '    specialArgs = { inherit inputs; };'
  echo '    modules = ['
  echo ''
  echo '      # ── Core ────────────────────────────────────────────'
  echo '      ./configuration.nix'
  for m in "${MODULES[@]}"; do
    echo "      ../../modules/$m"
  done
  if [ "$USE_AGENIX" = true ]; then
    echo ''
    echo '      # ── Agenix ──────────────────────────────────────────'
    echo '      inputs.agenix.nixosModules.default'
  fi
  if [ "$USE_HM" = true ]; then
    echo ''
    echo '      # ── Home Manager ────────────────────────────────────'
    echo '      inputs.home-manager.nixosModules.home-manager'
    echo '      {'
    echo '        home-manager.useGlobalPkgs = true;'
    echo '        home-manager.useUserPackages = true;'
    echo "        home-manager.users.$USERNAME = import ../../modules/home/$USERNAME/default.nix;"
    echo '      }'
  fi
  echo ''
  echo '    ];'
  echo '  };'
  echo '}'
} > "$OUTDIR/hosts/$HOSTNAME/$HOSTNAME.nix"

# ── hosts/<name>/configuration.nix ──────────────────────────────────

{
  echo "# hosts/$HOSTNAME/configuration.nix"
  echo '{ pkgs, ... }:'
  echo '{'
  echo '  imports = [ ./hardware-configuration.nix ];'
  echo ''
  echo '  # Bootloader (UEFI). For legacy BIOS use boot.loader.grub instead.'
  echo '  boot.loader.systemd-boot.enable = true;'
  echo '  boot.loader.efi.canTouchEfiVariables = true;'
  echo ''
  echo "  networking.hostName = \"$HOSTNAME\";"
  echo "  time.timeZone = \"$TIMEZONE\";"
  echo ''
  echo "  users.users.$USERNAME = {"
  echo '    isNormalUser = true;'
  echo "    description = \"$USERNAME\";"
  echo '    extraGroups = [ "wheel" "networkmanager" ];'
  echo '    # Add your SSH public key(s) here before enabling ssh-hardened:'
  echo '    # openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];'
  echo '  };'
  echo ''
  echo '  environment.systemPackages = with pkgs; ['
  echo '    vim'
  echo '    wget'
  echo '    curl'
  echo '  ];'
  echo ''
  echo '  # VM test settings — applied ONLY by `nixos-rebuild build-vm`,'
  echo '  # ignored entirely on a real installation. Sized from the machine'
  echo '  # that generated this config; adjust freely.'
  echo '  virtualisation.vmVariant = {'
  echo "    virtualisation.memorySize = $VM_MEM;"
  echo "    virtualisation.cores = $VM_CORES;"
  echo "    users.users.$USERNAME.initialPassword = \"test\";"
  echo '  };'
  echo ''
  echo "  system.stateVersion = \"$STATE_VERSION\"; # do not change after install"
  echo '}'
} > "$OUTDIR/hosts/$HOSTNAME/configuration.nix"

# ── hosts/<name>/hardware-configuration.nix (placeholder) ───────────

{
  echo '# PLACEHOLDER — replace before installing on real hardware:'
  echo "#   nixos-generate-config --show-hardware-config > hosts/$HOSTNAME/hardware-configuration.nix"
  echo '# This stub is sufficient for VM testing (nixos-rebuild build-vm);'
  echo '# a real install will refuse to build until it is replaced.'
  echo '{ }'
} > "$OUTDIR/hosts/$HOSTNAME/hardware-configuration.nix"

# ── home-manager stub ───────────────────────────────────────────────

if [ "$USE_HM" = true ]; then
  mkdir -p "$OUTDIR/modules/home/$USERNAME"
  {
    echo "# modules/home/$USERNAME/default.nix"
    echo '{ ... }:'
    echo '{'
    echo "  home.username = \"$USERNAME\";"
    echo "  home.homeDirectory = \"/home/$USERNAME\";"
    echo "  home.stateVersion = \"$STATE_VERSION\";"
    echo ''
    echo '  programs.git = {'
    echo '    enable = true;'
    echo '    # userName = "Your Name";'
    echo '    # userEmail = "you@example.com";'
    echo '  };'
    echo '}'
  } > "$OUTDIR/modules/home/$USERNAME/default.nix"
fi

# ── agenix stub ─────────────────────────────────────────────────────

if [ "$USE_AGENIX" = true ]; then
  mkdir -p "$OUTDIR/secrets"
  {
    echo '# secrets/secrets.nix — agenix recipient definitions.'
    echo '# Public keys only. NEVER commit private keys or plaintext secrets.'
    echo 'let'
    echo "  $USERNAME = \"REPLACE-WITH-YOUR-SSH-PUBLIC-KEY\";"
    echo "  $HOSTNAME = \"REPLACE-WITH-HOST-SSH-PUBLIC-KEY\"; # /etc/ssh/ssh_host_ed25519_key.pub"
    echo 'in'
    echo '{'
    echo "  # \"example.age\".publicKeys = [ $USERNAME $HOSTNAME ];"
    echo '}'
  } > "$OUTDIR/secrets/secrets.nix"
fi

# ── README ──────────────────────────────────────────────────────────

{
  echo "# $HOSTNAME NixOS configuration"
  echo ''
  echo 'Generated by space-elevator. Structure:'
  echo ''
  echo '- flake.nix — inputs and flake-parts entry'
  echo '- flake/hosts.nix — registers each host'
  echo "- hosts/$HOSTNAME/ — per-machine config"
  echo '- modules/ — reusable feature modules (importing a file enables it)'
  echo ''
  echo '## Test drive in a VM (no installation needed)'
  echo ''
  echo '```'
  echo 'git init && git add -A   # flakes only see tracked files'
  echo "nixos-rebuild build-vm --flake .#$HOSTNAME"
  echo "./result/bin/run-$HOSTNAME-vm"
  echo '```'
  echo ''
  echo 'Log in with your username and password `test` (VM only — real installs'
  echo "are unaffected). Delete $HOSTNAME.qcow2 for a factory-fresh boot."
  echo ''
  echo '## Installing on real hardware'
  echo ''
  echo '1. Replace the placeholder hardware config on the target machine:'
  echo '   ```'
  echo "   nixos-generate-config --show-hardware-config > hosts/$HOSTNAME/hardware-configuration.nix"
  echo '   ```'
  echo '2. Flakes only see files tracked by git:'
  echo '   ```'
  echo '   git init && git add -A'
  echo '   ```'
  echo '3. Build and switch:'
  echo '   ```'
  echo "   sudo nixos-rebuild switch --flake .#$HOSTNAME"
  echo '   ```'
  echo ''
  echo '## Adding another host'
  echo ''
  echo "Copy hosts/$HOSTNAME to hosts/<newname>, rename the files, adjust the"
  echo 'module list, and add one line to flake/hosts.nix.'
  if [ "$USE_AGENIX" = true ]; then
    echo ''
    echo '## Secrets (agenix)'
    echo ''
    echo 'Put your SSH *public* keys in secrets/secrets.nix, then create secrets with'
    echo '`agenix -e mysecret.age`. Encrypted .age files are safe to commit;'
    echo 'plaintext never touches the repo.'
  fi
} > "$OUTDIR/README.md"

# ── Done ────────────────────────────────────────────────────────────

COUNT="${#MODULES[@]}"
gum style \
  --border rounded --border-foreground 2 \
  --padding "1 2" --margin "1 0" \
  "Liftoff! Generated $OUTDIR with $COUNT modules." \
  "" \
  "Test drive it in a VM right now:" \
  "  cd $OUTDIR && git init && git add -A" \
  "  nixos-rebuild build-vm --flake .#$HOSTNAME" \
  "  ./result/bin/run-$HOSTNAME-vm    (login: $USERNAME / test)" \
  "" \
  "Install on real hardware:" \
  "  1. nixos-generate-config --show-hardware-config > hosts/$HOSTNAME/hardware-configuration.nix" \
  "  2. sudo nixos-rebuild switch --flake .#$HOSTNAME"

if gum confirm "Initialize a git repository in $OUTDIR now?"; then
  git -C "$OUTDIR" init -q
  git -C "$OUTDIR" add -A
  gum style --foreground 2 "Git repo initialized and files staged."
fi
