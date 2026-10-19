# What's included

Everything below comes with every install unless it says otherwise.
Anything on by default is still one line to switch off; see
[Configuring](./CONFIGURING.md).

## Gaming

- Steam with Proton-GE, gamescope and protontricks
- Heroic, Lutris and ProtonUp-Qt for games that aren't on Steam
- Feral GameMode, and MangoHud with GOverlay to configure it
- Controller drivers and permissions for Xbox (Bluetooth and the
  wireless dongle), PlayStation, Switch and 8BitDo pads
- The kernel tunables games need (`vm.max_map_count`, split-lock
  mitigation off)

## Handhelds

On a ROG Ally, Legion Go, Steam Deck, GPD Win, MSI Claw or AYANEO, the
installer recognises the machine and adds:

- Handheld Daemon, which drives the built-in gamepad, the vendor
  buttons' overlay, TDP presets and charge limits
- A Steam Big Picture session at the login screen, next to the desktop

## Hardware

- The GPU driver for your card (AMD, Intel or NVIDIA), detected
- PRIME offload on hybrid laptops, with the bus IDs filled in
- TLP power management on laptops
- Firmware updates (fwupd) and periodic SSD TRIM

## The desktop

You pick one of KDE Plasma, GNOME, COSMIC or Hyprland. Whichever you
choose comes with its own session, login manager and app store, plus:

- PipeWire audio, Bluetooth, and CUPS printing with network discovery
- Auto-mounting and phone (MTP) support
- Nerd Fonts and Noto
- Flatpak with Flathub, wired into the app store
- Firefox, Vesktop (a Discord client that shares audio with the screen
  on Wayland), kitty, mpv, LibreOffice, archive tools, GParted, and
  btop, ncdu and smartctl
- Catppuccin theming, system-wide

## Housekeeping

- NetworkManager and a firewall that drops by default
- zram swap and earlyoom
- Weekly Nix garbage collection
- nh, nvd and nix-tree
- `update.sh`, which updates everything in one command

## One line away

Off by default, each a single line in your config:

| Feature | Option |
|---|---|
| SteamOS-style Big Picture session at login (desktops) | `gaming.steam.gamescopeSession = true;` |
| Sunshine, for streaming to a Moonlight client | `gaming.streaming.enable = true;` |
| OpenRGB lighting control | `gaming.rgb.enable = true;` |
| Piper, for gaming mice | `gaming.controllers.mice = true;` |
| Zen or Xanmod kernel | `base.kernel = "zen";` |
| Docker and libvirt | `development.enable = true;` |
| KDE Connect (on by default with Plasma) | `desktop.kdeconnect.enable = true;` |

## What the installer asks

1. Hostname, username, and an optional login password
2. Which desktop
3. Whether you want the development tools (Docker and libvirt) and,
   outside Plasma, KDE Connect

Everything else is detected and confirmed with a keypress: GPU,
laptop or handheld, timezone, locale and keyboard layout.

## Module catalog

| Category | Options | Modules |
|---|---|---|
| Always on | `base`, `locale`, `network.*`, `tuning.*` | base (incl. kernel choice), locale, networkmanager, firewall, nix-gc, nix-tools, zram, earlyoom |
| With any desktop | `desktop.*` | audio, bluetooth, printing, fonts, packages, gvfs, flatpak |
| Standard | `gaming.*`, `desktop.theming` | steam, gamemode, launchers, controllers, sysctl, Catppuccin |
| Pick one desktop | `desktop.plasma` / `gnome` / `cosmic` / `hyprland` | session, login manager, app store and native apps |
| Detected | `gpu.amd` / `gpu.intel` / `gpu.nvidia`, `tuning.tlp`, `gaming.handheld` | drivers and PRIME, laptop power, Handheld Daemon |
| Opt-in | `gaming.streaming`, `gaming.rgb`, `gaming.controllers.mice`, `gaming.steam.gamescopeSession` | Sunshine, OpenRGB, Piper, Big Picture session |
| Optional extras | `development`, `desktop.kdeconnect` | Docker and libvirt, KDE Connect |
