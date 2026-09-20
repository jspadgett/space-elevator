# Upgrading an existing system

Moves a machine that's already running a Space Elevator config onto the
current modules, keeping your disks, your user and your additions.

**First, the honest answer: you may not need to do this.** Your config
is self-contained plain NixOS. It doesn't phone home, nothing expires,
and `./update.sh` keeps nixpkgs current without any of this. Upgrade
because you want the new gaming stack and the option-based switches —
not because you have to.

Two things to know before starting:

- **You can't lose your system.** Everything here is reversible, and
  even a switch that goes wrong is one reboot away from the old
  generation. Nothing is deleted.
- **Set aside an hour**, most of it downloads. The new baseline pulls
  in Steam, Heroic, Lutris, Firefox and Vesktop — several GB.

## The short version

On the machine you're upgrading:

```sh
nix run github:jspadgett/space-elevator#upgrade
```

It reads your existing config, shows you what it found, regenerates it
with the current modules, and carries across the things the wizard
can't know — your hardware configuration, `system.stateVersion`, your
declared password, and which features you had on. Then it builds
*without touching the running system*, shows you what would change, and
switches only if you say yes. Your old config is moved aside, not
deleted.

Useful flags:

| | |
|---|---|
| `--no-switch` | generate and build, change nothing. A safe way to see what you'd get. |
| `--no-build` | generate only, don't compile |
| `--config <path>` | if your config isn't at `/etc/nixos` |
| `--yes` | don't prompt |

Afterwards, read `UPGRADE-NOTES.md` in the new config. It lists what
carried over, what didn't, and anything of yours that needs moving by
hand — the script reports those rather than guessing at them.

**What it can't do for you:** merge your own additions to
`configuration.nix` (extra packages, services, users) or your own
modules. Nix isn't safely mergeable by a shell script, so it hands you
a diff instead and tells you what to look at.

The rest of this page is the same job done by hand — worth following if
you'd rather see every step, or if your config has drifted far enough
from a generated one that the script's detection is worth double-checking.

---

# Doing it by hand

## Step 1 — Find your current config and back it up

It's wherever `nixos-rebuild` points, usually `/etc/nixos`:

```sh
ls /etc/nixos
```

Copy the whole thing somewhere safe. Not a move — a copy:

```sh
sudo cp -a /etc/nixos ~/nixos-backup
```

If it's a git repo (the wizard offers to make one), commit first so you
have a point to return to:

```sh
cd /etc/nixos
sudo git add -A
sudo git commit -m "before regenerating"
```

## Step 2 — Write down what has to carry over

Open `hosts/<YOURHOST>/configuration.nix` and note these. The wizard
can't know any of them.

| What | Where it is | Why it matters |
|---|---|---|
| `system.stateVersion` | bottom of `configuration.nix` | **The one that bites.** It records which NixOS release this machine was *first installed* with, and some services (databases especially) read it to decide on-disk formats. It is not a version to keep current — it must stay exactly as it is, forever. |
| Hostname | `networking.hostName` | Give the wizard the same one and every path stays familiar |
| Username | `users.users.<name>` | Must match your existing account |
| Anything you added by hand | extra `environment.systemPackages`, extra users, services, firewall ports, boot tweaks | The wizard writes a fresh `configuration.nix`; your additions are yours to move |
| Hand-edits to `hardware-configuration.nix` | LUKS devices, btrfs subvolume options, extra `boot.initrd` modules | Step 4 |

Keep that file open in another window. You'll copy from it in step 6.

## Step 3 — Run the wizard

Run it as your normal user, **on the machine you're upgrading** — that's
what lets it read your real hardware:

```sh
nix run github:jspadgett/space-elevator
```

Answers to give:

- **Hostname** — the same one you noted. Different is allowed, it just
  changes the flake attribute you rebuild against.
- **Username** — must match your existing account.
- **Password** — read the next paragraph before typing anything.
- **Output directory** — accept the default `./nixos-config`. You'll
  move it into place at the end, once you've checked it.
- **"Capture THIS machine's hardware config?"** — **yes**. This runs
  `nixos-generate-config` against your running system and writes a real
  hardware config instead of the placeholder.
- **GPU, battery, hybrid graphics** — detected; confirm what it found.
- **Flavors** — Development and KDE Connect are the only questions.
  Gaming, theming and Firefox come as standard.

**About the password.** On a machine that already exists:

- *Leave it blank* and the wizard writes `initialPassword`, which NixOS
  only applies when creating a new account. Your current password is
  untouched. This is what you want.
- *Type one* and it writes `hashedPassword`, which is declarative and
  **will replace your login password** at the next rebuild. Only do this
  if you mean to change it.

## Step 4 — Check the captured hardware config

The wizard regenerated this from the running system, so it's accurate —
unless you had hand-edited the old one. Compare them:

```sh
diff /etc/nixos/hosts/<YOURHOST>/hardware-configuration.nix \
     ~/nixos-config/hosts/<YOURHOST>/hardware-configuration.nix
```

Expect small differences in UUIDs formatting or kernel module lists —
those are fine. What you're looking for is anything *you* put there:
`boot.initrd.luks.devices`, btrfs `options = [ "subvol=..." "compress=zstd" ]`,
custom `swapDevices`, an unusual `boot.initrd.availableKernelModules`.

If you find any, copy the old file over the new one:

```sh
cp /etc/nixos/hosts/<YOURHOST>/hardware-configuration.nix \
   ~/nixos-config/hosts/<YOURHOST>/hardware-configuration.nix
```

If the diff is empty or only cosmetic, keep the new one.

## Step 5 — Restore `system.stateVersion`

Open `~/nixos-config/hosts/<YOURHOST>/configuration.nix`. At the bottom:

```nix
  system.stateVersion = "26.05"; # do not change after install
```

Replace `"26.05"` with whatever your old config said. If your machine was
first installed with 25.05, it stays `"25.05"` — no matter how new the
rest of the system is.

## Step 6 — Move your own additions across

From the old `configuration.nix` into the new one: extra packages, extra
users, services you enabled, firewall ports, boot loader tweaks. Two of
these now have proper homes instead:

```nix
# old: networking.firewall.allowedTCPPorts = [ 8080 ];
# new, in space-elevator.nix:
spaceElevator.network.firewall.allowedTCPPorts = [ 8080 ];
```

If you had any modules of your own under `modules/`, copy them in and add
them to the host's `modules` list in `hosts/<YOURHOST>/<YOURHOST>.nix`.

## Step 7 — Check the switches match what you had

Open `hosts/<YOURHOST>/space-elevator.nix`. The wizard filled it in from
your answers, and most of the old baseline is automatic now. Worth a
read anyway — this is the file you'll be living in from now on, and it
lists what's available as commented lines.

Old import lines translate like this:

| You used to import | Now |
|---|---|
| `common/base.nix`, `common/base-locale.nix` | automatic; `locale.*` holds the values |
| `desktop/audio`, `bluetooth`, `printing`, `nerdfonts`, `desktop-packages`, `tuning/gvfs` | automatic with any desktop |
| `network/*`, `tuning/nix-gc`, `nix-tools`, `zram`, `earlyoom`, `apps/flatpak` | automatic |
| `desktop/plasma.nix` etc. | `desktop.plasma.enable = true;` |
| `gpu/amdgpu.nix` / `intel-gpu.nix` / `nvidia.nix` | `gpu.amd` / `gpu.intel` / `gpu.nvidia` `.enable = true;` |
| `tuning/tlp.nix` | `tuning.tlp.enable = true;` |
| `gaming/steam.nix`, `gamemode.nix` | automatic — `gaming.enable = false;` to opt out |
| `desktop/theming.nix` | automatic |
| `apps/docker.nix`, `virtualisation.nix` | `development.enable = true;` |
| `desktop/kdeconnect.nix` | `desktop.kdeconnect.enable = true;` (automatic on Plasma) |

**NVIDIA**: bus IDs you edited into the old module are options now.

```nix
    gpu.nvidia = {
      enable = true;
      prime = {
        enable = true;
        intelBusId = "PCI:0:2:0";     # or amdgpuBusId
        nvidiaBusId = "PCI:1:0:0";
      };
    };
```

On a hybrid laptop the wizard fills these in for you. A pre-Turing card
(GTX 10xx / 9xx) is `gpu.nvidia.driver = "legacy_580";` instead of
editing the module by hand.

## Step 8 — Build it without switching

This is the safe test. It compiles everything and touches nothing:

```sh
cd ~/nixos-config
git add -A                 # flakes only see tracked files
sudo nixos-rebuild build --flake .#<YOURHOST>
```

This is where the downloads happen, so give it time. If it fails, your
running system is entirely unaffected — fix the error and run it again.

Curious what's about to change? Compare the closures:

```sh
nvd diff /run/current-system ./result
```

## Step 9 — Put it in place and switch

Move the old config aside and the new one in:

```sh
sudo mv /etc/nixos /etc/nixos.old
sudo mv ~/nixos-config /etc/nixos
cd /etc/nixos
sudo nixos-rebuild switch --flake .#<YOURHOST>
```

Prefer a dress rehearsal first? `sudo nixos-rebuild test --flake .#<YOURHOST>`
activates the new system without adding a boot entry — a reboot undoes it
completely.

Then log out and back in, so your desktop session picks up the new one.

## Step 10 — Check it over

```sh
systemctl --failed              # should be empty
nvidia-smi                      # NVIDIA machines
steam                           # and launch something
```

Also worth a look: sound, Bluetooth, your printer, and a controller if
you use one.

---

## If something's wrong

**Reboot and pick the previous generation** in the boot menu. That's the
whole recovery procedure — you're back exactly where you started, and
`/etc/nixos.old` is still sitting there to switch back to:

```sh
sudo nixos-rebuild switch --flake /etc/nixos.old#<YOURHOST>
```

## Later, once you're happy

Keep the old generations for a week or two — they're your rollback. When
you no longer want them:

```sh
sudo rm -rf /etc/nixos.old ~/nixos-backup
sudo nix-collect-garbage --delete-older-than 14d
```

---

## Are you also changing NixOS release?

Check `nixpkgs.url` in your old `flake.nix` against the new one. If the
old says `nixos-25.11` and the new says `nixos-26.05`, this upgrade is
*also* a NixOS release upgrade — two changes at once.

That's usually fine, but it means a package somewhere may have changed
behavior in a way that has nothing to do with Space Elevator. If you'd
rather separate the two, edit the new `flake.nix` back to your old
release before step 8, get everything working, then bump it and rebuild
as a second step.

`system.stateVersion` stays at its original value either way. It is not
part of this.
