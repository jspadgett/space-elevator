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

```sh
/etc/nixos/update.sh
```

This updates everything in one go: Space Elevator itself, every
package, and NixOS when a new release comes out (it asks before that
one). It builds first, shows what will change, and only switches when
you say yes.

Installed before updates covered Space Elevator's modules? `update.sh`
will tell you, and [Upgrading](./docs/UPGRADING.md) walks through the
one-time switch.

## Docs

- [Installing](./docs/INSTALL.md): from a blank USB stick to a working system
- [What's included](./docs/FEATURES.md): everything you get, and what's one line away
- [Configuring](./docs/CONFIGURING.md): turning features on and off, adding packages, using the modules in your own flake
- [Upgrading](./docs/UPGRADING.md): moving an older install onto the updatable layout
- [Developing](./docs/DEVELOPING.md): tests, adding modules, cutting releases

## License

[MIT](./LICENSE). Generated configurations are yours to do with as you please.
