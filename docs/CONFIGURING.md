# Configuring

Your configuration lives in `/etc/nixos`. It's plain NixOS: you can
change anything, and nothing gets overwritten behind your back.

## The files

| File | What's in it |
|---|---|
| `hosts/<name>/space-elevator.nix` | The feature switches for this machine |
| `hosts/<name>/configuration.nix` | Your user, the bootloader, extra packages |
| `hosts/<name>/hardware-configuration.nix` | Disks and filesystems, captured at install |
| `flake.nix` / `flake.lock` | Inputs, Space Elevator among them, and the exact versions in use |
| `update.sh` | Updates everything; see below |

## Turning features on and off

Open `hosts/<name>/space-elevator.nix`. Every feature is one line, and
the commented-out lines show what else is available:

```nix
spaceElevator = {
  enable = true;
  user.name = "alice";

  desktop.plasma.enable = true;      # switch desktops by changing this line
  desktop.theming.flavor = "latte";  # light theme instead

  gpu.nvidia = {
    enable = true;
    prime = {                        # hybrid laptop, detected and filled in
      enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  development.enable = true;         # Docker + libvirt
  # gaming is already on: gaming.enable = false; to opt out
};
```

Then apply it:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#<name>
```

Nothing extra is downloaded to turn a feature on. Every module is
already on your machine, switched off.

**Big switches set defaults, small ones win.** `gaming.enable` turns on
everything under it, but `gaming.gamemode.enable = false;` still turns
GameMode off. The same goes for the standard pieces:
`desktop.packages.firefox = false;`, `desktop.theming.enable = false;`,
`gaming.steam.protonGE = false;`.

**Switching desktops** is changing the one `desktop.*.enable` line,
rebuilding, and logging out. Audio, Bluetooth, printing, fonts, the
apps, Steam and the theme stay the same whichever you pick.

Each option has a description in its module explaining what it does.

## Adding packages

Install apps from your desktop's app store (Discover, GNOME Software or
COSMIC Store); they come from Flathub and need no config changes.

For system packages, add them to `environment.systemPackages` in
`hosts/<name>/configuration.nix` and rebuild. Package names are at
[search.nixos.org](https://search.nixos.org/packages).

## Modules of your own

Put them in a `modules/` directory in your config and add each one to
the `modules` list in `hosts/<name>/<name>.nix`, below
`./space-elevator.nix`.

## Updating

```sh
/etc/nixos/update.sh
```

In one go it moves:

- Space Elevator's modules to the newest release
- nixpkgs, and onto the next NixOS release when Space Elevator moves to
  one. It asks first, and `system.stateVersion` never changes.
- every other input

Then it builds without touching the running system, shows what would
change, and switches when you say yes. If your config is a git
repository, each update is committed, so `git revert` undoes it.

| Flag | Does |
|---|---|
| `--check` | Only says whether a new release is out |
| `--no-switch` | Updates and builds, leaves the running system alone |
| `--yes` | No questions |

If an update breaks something, reboot and pick the previous entry in
the boot menu.

Your config follows the `stable` branch, which only ever points at a
tagged release. `flake.lock` pins the exact version, so builds are
reproducible until you update.

## Using the modules in your own flake

You don't need the installer to use the modules. They're a flake
output:

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

Importing them declares the options and turns nothing on. Theming
needs the [catppuccin](https://github.com/catppuccin/nix) module too;
without it the system builds unthemed and warns you.
