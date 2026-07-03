# 🚀 Space Elevator

**Your NixOS desktop, built to order.** Answer four questions — hostname, username, desktop environment, flavors — and get a complete, ready-to-boot NixOS desktop flake with distro-grade defaults. Hardware is auto-detected and confirmed, not interrogated.

## Quick start

```sh
nix run github:jspadgett/space-elevator
```

If Nix complains about experimental features:

```sh
nix run --experimental-features 'nix-command flakes' github:jspadgett/space-elevator
```

That's it. No cloning, no setup. It also works from the NixOS installer
ISO: partition and mount your disks at /mnt as usual, run the tool, and
it will detect the installer environment and set everything up for
`nixos-install`. The generated configuration lands in `./nixos-config` (configurable), complete with its own README covering first-boot steps.

## What you get without asking

Like any good desktop distro, the baseline just works. Every generated config includes:

**Hardware & drivers** — GPU driver matched to your detected card (AMD / Intel / NVIDIA), firmware updates (fwupd), periodic SSD TRIM, TLP power management on laptops.

**Desktop plumbing** — PipeWire audio, Bluetooth, CUPS printing with network discovery, auto-mounting and MTP support (gvfs/udisks2), Nerd Fonts + Noto, everyday apps, Flatpak with Flathub pre-configured.

**System sanity** — NetworkManager, a drop-by-default firewall, zram swap, earlyoom, automatic Nix garbage collection, and quality-of-life Nix tooling (nh, nvd, nix-tree).

**A GUI app store** — Discover, GNOME Software, or COSMIC Store wired to Flathub, so installing apps never requires editing a config file. Plus a generated `update.sh` for one-command system updates, with NixOS generation rollback as the safety net.

## The questions

1. **Hostname**, **username**, and an optional **login password** (hashed into the config so first boot just works)
2. **Desktop environment** — KDE Plasma, GNOME, COSMIC, or Hyprland
3. **Flavors** — optional bundles: Gaming (Steam + gamemode), Development (Docker + libvirt), Catppuccin theming, KDE Connect

Everything else is detected from the machine and confirmed with a keypress: GPU vendor, laptop vs. desktop, timezone, locale, and keyboard layout. On NixOS it offers to capture your real hardware configuration; in the installer ISO it sets up for `nixos-install` directly.

## Non-interactive mode

Set `SE_NONINTERACTIVE=1` plus any `SE_*` variables (see the header of `scaffold.sh`) to generate without prompts — useful for scripting and CI. The test suite in `tests/run.sh` uses this to generate and verify a config for every desktop environment, and CI evaluates each one against nixpkgs.

## Design principles

**Defaults over decisions.** Anything with an obviously correct answer for a desktop is baked in. You choose identity (hostname, user, DE, flavors); the tool handles plumbing.

**Self-contained.** Every module is vendored in this repository under `modules/`. Nothing is fetched at run time, so output is reproducible and auditable.

**Import-is-enable.** Modules contain no options plumbing. Importing a file turns the feature on; deleting the import line turns it off. The baseline is just imports too — nothing is locked in.

**No framework dependency.** The output is plain Nix. Once generated, the configuration is entirely yours.

## Module catalog

| Category | Modules |
|---|---|
| **Baseline (always)** | base · base-locale · audio · bluetooth · printing · nerdfonts · desktop-packages · networkmanager · firewall · flatpak · nix-gc · nix-tools · zram · gvfs · earlyoom |
| **Detected** | amdgpu / intel-gpu / nvidia · tlp (laptops) |
| **Desktop (pick one)** | plasma · gnome · cosmic · hyprland (each with its app store) |
| **Flavors (optional)** | steam + gamemode · docker + virtualisation · theming (Catppuccin) · kdeconnect |

## Extending

Adding a module takes two steps:

1. Drop a `.nix` file into the appropriate `modules/` category.
2. Add it to the baseline array or a flavor line in `scaffold.sh`.

No schema, no manifest, no codegen. Modules that need the user's name can use the `@USERNAME@` placeholder — it's substituted automatically.

## Requirements

- Nix with flakes enabled (`experimental-features = nix-command flakes`)

## Contributing

Issues and pull requests are welcome. New modules should follow the import-is-enable convention: no options declarations, no cross-module dependencies, one feature per file.

## License

[MIT](./LICENSE) — use it, fork it, ship it. Generated configurations are yours to do with as you please.
