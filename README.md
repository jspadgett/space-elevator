# 🚀 Space Elevator

**From bare metal to orbit.** An interactive generator for complete, modular NixOS flake configurations — answer a few questions in your terminal and get a ready-to-boot flake built on the [flake-parts](https://github.com/hercules-ci/flake-parts) host pattern with one-file-per-feature modules.

## Quick start

```sh
nix run github:jspadgett/space-elevator
```

That's it. No cloning, no setup. You'll be prompted for:

- Hostname and username
- Timezone
- GPU vendor
- Desktop environment
- Feature modules to include

The generated configuration lands in `./nixos-config` (configurable), complete with its own README covering first-boot steps.

## Why this exists

Starting a NixOS configuration from scratch means making a dozen structural decisions before you've written a single line: flake layout, module organization, options plumbing, host separation. Space Elevator makes those decisions for you with a pattern that stays maintainable as your config grows — then gets out of the way. The output is plain Nix with no framework dependency on this tool; once generated, the configuration is entirely yours.

## Design principles

**Self-contained.** Every module offered by the generator is vendored in this repository under `modules/`. Nothing is fetched from any personal configuration at run time, so output is reproducible and auditable.

**Import-is-enable.** Modules contain no options plumbing. Importing a file turns the feature on; deleting the import line turns it off. Your generated config stays readable at a glance.

**Sane exclusivity.** Mutually exclusive choices are single-select — one desktop environment, one GPU vendor. Complementary features (say, zram alongside a swapfile) can be freely combined.

**Optional inputs stay optional.** `home-manager`, `agenix`, and `catppuccin` only appear as inputs in the generated `flake.nix` if you actually select them. No dead weight in your lock file.

## Module catalog

| Category | Modules |
|---|---|
| **Core** | base · base-locale · base-agenix |
| **Desktop** | plasma · hyprland · cosmic · gnome · audio (PipeWire) · bluetooth · printing · nerdfonts · theming (Catppuccin) · desktop-packages |
| **GPU** | amdgpu · intel-gpu · nvidia |
| **Network** | networkmanager · tailscale · mullvad · ssh-hardened · fail2ban · mtr |
| **Gaming** | steam · gamemode |
| **Apps** | flatpak · appimage · signal · virtualisation · docker |
| **Tuning** | nix-gc · nix-tools · zram · swapfile · earlyoom · ssd · firewall · auto-upgrade · tlp · shell-zsh · gpgagent · gvfs · syncthing |

## Extending

Adding a module takes two steps:

1. Drop a `.nix` file into the appropriate `modules/` category.
2. Add one `add_if`/menu line in `scaffold.sh`.

That's the entire registration process — no schema, no manifest, no codegen.

## Requirements

- Nix with flakes enabled (`experimental-features = nix-command flakes`)

## Contributing

Issues and pull requests are welcome. New modules should follow the import-is-enable convention: no options declarations, no cross-module dependencies, one feature per file.

## License

[MIT](./LICENSE) — use it, fork it, ship it. Generated configurations are yours to do with as you please.
