# Space Elevator



![CI](https://github.com/jspadgett/space-elevator/actions/workflows/ci.yml/badge.svg)



**Space Elevator gets you to gaming orbit.** A NixOS-based installer for
gaming desktops and handhelds.

Flash the ISO, answer a few questions, and you get a NixOS system set up
for games: Steam with Proton-GE, Heroic and Lutris for everything else,
the right GPU driver, and controller support. On handhelds like the ROG
Ally, Legion Go and Steam Deck, it also sets up Handheld Daemon and a
Big Picture session. Updates are one command, and if one goes wrong,
the previous system is still in the boot menu.

Underneath, it's plain NixOS. Every feature is one line in a config you
own, and all of nixpkgs is there when you want more.

## Install

1. Download the ISO from the [latest release](https://github.com/jspadgett/space-elevator/releases/latest).
2. Flash it to a USB stick with [balenaEtcher](https://etcher.balena.io/) or `dd`.
3. Boot from it. The installer starts on its own and handles Wi-Fi, the
   disk and the install. You can drive it with a keyboard or a gamepad.

New to NixOS? The [step-by-step guide](./docs/INSTALL.md) covers boot
menus, Secure Boot and the rest.

**Already running NixOS?** `nix run github:jspadgett/space-elevator`
generates a config for the machine you're on, without reinstalling.

## Keeping it current

`./update.sh` in your config updates everything in one go: Space
Elevator itself, every package, and NixOS when a new release comes out
(it asks before that one). It builds first, shows what will change,
and only switches when you say yes.

## What you get without asking

Like any good desktop distro, the baseline just works. Every generated config includes:

**Gaming** — Steam with Proton-GE, gamescope and protontricks; Heroic, Lutris and ProtonUp-Qt for everything that isn't on Steam; Feral GameMode; MangoHud with GOverlay to configure it; drivers and permissions for Xbox (Bluetooth *and* the wireless dongle), PlayStation, Switch and 8BitDo pads; and the kernel tunables games need (`vm.max_map_count`, split-lock mitigation off). This is a gaming distro; you don't get asked.

**One line away** — a SteamOS-style Big Picture session at login (`gaming.steam.gamescopeSession`), Sunshine for streaming to a Moonlight client, OpenRGB, Piper for gaming mice, and a Zen or Xanmod kernel (`base.kernel = "zen"`).

**Hardware & drivers** — GPU driver matched to your detected card (AMD / Intel / NVIDIA), PRIME offload configured automatically on hybrid laptops, firmware updates (fwupd), periodic SSD TRIM, TLP power management on laptops.

**Desktop plumbing** — PipeWire audio, Bluetooth, CUPS printing with network discovery, auto-mounting and MTP support (gvfs/udisks2), Nerd Fonts + Noto, Flatpak with Flathub pre-configured.

**Everyday apps** — Firefox, Vesktop (a Discord client whose screen sharing carries audio on Wayland), kitty, mpv, LibreOffice, archive tools, GParted with the filesystem backends, and the usual diagnostics (btop, ncdu, smartctl). The same set on every desktop.

**A look** — Catppuccin theming system-wide, out of the box. Four flavors and fourteen accents, one line apart.

**System sanity** — NetworkManager, a drop-by-default firewall, zram swap, earlyoom, automatic Nix garbage collection, and quality-of-life Nix tooling (nh, nvd, nix-tree).

**A GUI app store** — Discover, GNOME Software, or COSMIC Store wired to Flathub, so installing apps never requires editing a config file. Plus a generated `update.sh` that updates the modules, nixpkgs and everything else in one command, with NixOS generation rollback as the safety net.

## The questions

1. **Hostname**, **username**, and an optional **login password** (hashed into the config so first boot just works)
2. **Desktop environment** — KDE Plasma, GNOME, COSMIC, or Hyprland
3. **Flavors** — the two genuinely optional bundles: Development (Docker + libvirt) and KDE Connect (already included with Plasma)

Everything else is detected from the machine and confirmed with a keypress: GPU vendor, laptop vs. desktop, timezone, locale, and keyboard layout. On NixOS it offers to capture your real hardware configuration; in the installer ISO it sets up for `nixos-install` directly.

## Non-interactive mode

Set `SE_NONINTERACTIVE=1` plus any `SE_*` variables (see the header of `scaffold.sh`) to generate without prompts — useful for scripting and CI.

## Tests

| What | How |
|---|---|
| The wizard writes the right switches | `bash tests/run.sh` — generates a config for every desktop, GPU and flavor combination and checks the output |
| Updates and upgrades do what they say | `bash tests/run.sh` — runs the upgrade on every layout that has shipped, and the updater against local stand-ins for GitHub: new releases, a NixOS release change, a failed build, a declined move |
| The modules actually work | `nix flake check` — [tests/checks.nix](./tests/checks.nix) evaluates every feature combination, proves importing the set turns nothing on, and verifies each assertion fires on the config it was written for |
| The generated config builds | CI evaluates the VM derivation for each desktop and GPU |
| The installer ISO builds | CI evaluates the ISO derivation |

## Design principles

**Defaults over decisions.** Anything with an obviously correct answer for a gaming desktop is baked in — Steam, a browser, a theme. You choose identity (hostname, user, desktop); the tool handles the rest. Every baked-in default is still one line to remove.

**One update path.** A generated config takes Space Elevator as a flake input that follows the `stable` branch, which only ever points at a release. Your flake.lock pins the exact modules in use, so builds stay reproducible and auditable, and turning on a feature never fetches anything new. `./update.sh` moves the modules, nixpkgs and every other input forward together, so there is no second, manual step for getting new modules.

**Everything is an option.** Modules declare `spaceElevator.*` options and stay dormant until enabled. Your answers become a single file — `hosts/<name>/space-elevator.nix` — where every feature is one line you can flip:

```nix
spaceElevator = {
  enable = true;
  user.name = "alice";

  desktop.plasma.enable = true;      # switch desktops by changing this line
  desktop.theming.flavor = "latte";  # theming is on; this picks the shade

  gpu.nvidia = {
    enable = true;
    prime = {                        # hybrid laptop, detected and filled in
      enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  development.enable = true;         # Docker + libvirt
  # gaming is already on — gaming.enable = false; to opt out
};
```

**Desktops are flavors.** Picking a desktop brings its session, login manager, app store and native companions — and the shared plumbing behind it (audio, Bluetooth, printing, fonts, removable media, the common app set, Firefox, Steam, the theme) is deliberately identical whichever one you choose.

**Rollups, not lock-in.** `gaming.enable` sets the defaults for everything under it; `gaming.gamemode.enable = false` still wins. Nothing baked in is all-or-nothing — `desktop.packages.firefox = false`, `desktop.theming.enable = false`, `gaming.steam.protonGE = false`.

**No framework dependency.** The output is plain Nix — the NixOS module system and nothing else. Once generated, the configuration is entirely yours.

## Module catalog

| Category | Option | Modules |
|---|---|---|
| **Baseline (always)** | `base`, `locale`, `network.*`, `tuning.*` | base (incl. kernel choice) · locale · networkmanager · firewall · nix-gc · nix-tools · zram · earlyoom |
| **Desktop plumbing** | `desktop.*` | audio · bluetooth · printing · fonts · packages (Firefox, Vesktop, the app set) · gvfs · flatpak |
| **Standard with any desktop** | `gaming.*`, `desktop.theming` | steam · gamemode · launchers · controllers · sysctl · Catppuccin |
| **Desktop (pick one)** | `desktop.plasma` / `gnome` / `cosmic` / `hyprland` | session, login manager, app store and native apps |
| **Detected** | `gpu.amd` / `gpu.intel` / `gpu.nvidia`, `tuning.tlp`, `gaming.handheld` | drivers, PRIME offload on hybrid laptops, laptop power management, Handheld Daemon and a Big Picture login session on handheld PCs (ROG Ally, Legion Go, Steam Deck…) |
| **Opt-in** | `gaming.streaming`, `gaming.rgb`, `gaming.controllers.mice`, `gaming.steam.gamescopeSession` | Sunshine · OpenRGB · Piper · Big Picture session |
| **Flavors (optional)** | `development`, `desktop.kdeconnect` | docker + virtualisation · KDE Connect (included with Plasma) |

## Using the modules without the wizard

The module set is a flake output, so you can skip generation entirely:

```nix
{
  inputs.space-elevator.url = "github:jspadgett/space-elevator/stable";

  # in your nixosSystem modules:
  imports = [ inputs.space-elevator.nixosModules.default ];
  spaceElevator = {
    enable = true;
    desktop.gnome.enable = true;
  };
}
```

Importing it declares the options and turns nothing on.

## Extending

Adding a module takes two steps:

1. Drop a `.nix` file into the appropriate `modules/` category, declaring `options.spaceElevator.<category>.<name>.enable` and wrapping its config in `lib.mkIf`.
2. Add it to that category's `default.nix` imports.

The option path mirrors the directory layout. A feature that should follow its category's rollup takes `default = config.spaceElevator.<category>.enable;`. Modules that need the primary user's name read `config.spaceElevator.user.name`.

New modules should come with a test in `tests/checks.nix` — an `evalCheck` at minimum, and an `expect` if the feature has behavior worth pinning down.

## Releasing

`stable` is what every installed machine's `./update.sh` follows, so it
only moves through [the release workflow](./.github/workflows/release.yml):

1. On main, bump `version` in [release.nix](./release.nix). When the lock
   moves to a new NixOS release, bump `nixosRelease` with it —
   `nix flake check` fails if the two disagree.
2. `git tag v<version> && git push origin v<version>`.

The workflow runs the full CI suite on the tag, checks the tag against
`release.nix` and that it is on main, then fast-forwards `stable`. To
pull a bad release, run the workflow by hand with the previous tag and
"rollback" ticked.

## Requirements

- Nix with flakes enabled (`experimental-features = nix-command flakes`)

## Contributing

Issues and pull requests are welcome. New modules should follow the import-is-enable convention: no options declarations, no cross-module dependencies, one feature per file.

## License

[MIT](./LICENSE) — use it, fork it, ship it. Generated configurations are yours to do with as you please.
