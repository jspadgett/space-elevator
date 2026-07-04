# Installing NixOS with Space Elevator — the complete beginner's guide

Never used NixOS before? This walks you from a blank USB stick to a
working desktop, no prior Nix knowledge needed. Total time: about an
hour, most of it downloads.

**⚠️ The install erases the target disk completely.** Back up anything
you care about before starting.

## What you need

- A USB stick (4 GB or larger — it gets erased too)
- The computer you're installing on, with internet access
- 30 GB or more of disk you're willing to wipe

## Step 1 — Download NixOS and flash the USB

Download the **Graphical ISO (GNOME)** from
[nixos.org/download](https://nixos.org/download/). The graphical one is
easier for this guide even though we won't use its built-in installer —
it gives you a normal desktop with Wi-Fi settings and a terminal.

Flash it to the USB stick with [balenaEtcher](https://etcher.balena.io/)
(Windows/Mac/Linux, point-and-click) or, on Linux:

```
sudo dd if=nixos-*.iso of=/dev/sdX bs=4M status=progress
```

(`/dev/sdX` is your USB stick — check with `lsblk` first. Getting this
wrong overwrites the wrong disk.)

## Step 2 — Boot the USB

1. Plug in the stick and restart. Mash the boot-menu key as it powers
   on — usually **F12**, sometimes F2, F10, Esc, or Del.
2. If the stick doesn't appear, enter firmware setup and **disable
   Secure Boot** — stock NixOS doesn't support it.
3. Pick the USB stick. You'll land on a GNOME desktop running from the
   stick. **Ignore the "Install NixOS" icon** — we're doing something
   better.

Connect to the internet (Wi-Fi lives in the system menu, top right).

## Step 3 — Partition the disk

Open a terminal (press the Super/Windows key, type "terminal"). Find
your target disk:

```
lsblk
```

Disks look like `sda` or `nvme0n1`; ignore the entries for the USB
stick you booted from (its size gives it away). The commands below use
`/dev/nvme0n1` — **replace it with yours everywhere**. On `sda`-style
disks, partitions are `sda1`/`sda2` instead of `nvme0n1p1`/`nvme0n1p2`.

```
sudo -i
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 513MiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root ext4 513MiB 100%
```

That's the whole layout: a small boot partition and one big root. No
swap partition needed — the generated config uses compressed RAM swap
(zram) instead.

Format and mount them:

```
mkfs.fat -F 32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos /dev/nvme0n1p2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
```

Your future system now lives (empty) at `/mnt`.

## Step 4 — Run Space Elevator

Still in the root terminal:

```
cd /mnt/etc && mkdir -p nixos && cd nixos
nix run --experimental-features 'nix-command flakes' github:jspadgett/space-elevator
```

Answer the questions. Two matter specially here:

- **Output directory:** enter `.` (a single dot — right here). This
  puts your config at `/mnt/etc/nixos`, which becomes `/etc/nixos` on
  the installed system. *Don't* use the default or your home folder —
  the live session's home is a RAM disk and vanishes on reboot.
- **"Installer environment detected … set up for nixos-install?"**
  Say **yes**. This captures your real disk layout automatically.

Everything else is normal: pick a hostname, username, password, desktop,
and any flavors. Say yes to the git question at the end.

## Step 5 — Install

```
nixos-install --flake /mnt/etc/nixos#YOURHOSTNAME
```

(Use the hostname you chose.) This downloads and assembles your whole
desktop — 10 to 30 minutes. At the end it asks for a **root password**;
pick one and remember it, it's your emergency key.

Then:

```
reboot
```

Pull the USB stick out as it restarts.

## Step 6 — First boot

You'll get a boot menu (that's the generation menu — remember it, it
matters later), then your desktop's login screen. Log in with your
username and the password you chose in the wizard.

That's it. You're running NixOS.

## Everyday life on your new system

**Installing apps:** open the app store (Discover on Plasma, Software
on GNOME, Store on COSMIC) and install from Flathub with a click. No
config editing needed.

**Updating everything:**

```
cd /etc/nixos
sudo bash update.sh
```

**If an update breaks something:** reboot and pick the *previous* entry
in the boot menu. The whole system rolls back to exactly how it was.
This is NixOS's superpower — you can never permanently break your
machine with an update.

**Adding system packages by hand** (when you're ready to peek under the
hood): edit `/etc/nixos/hosts/YOURHOSTNAME/configuration.nix`, add a
package name to the `environment.systemPackages` list, then:

```
cd /etc/nixos
sudo git add -A
sudo nixos-rebuild switch --flake .#YOURHOSTNAME
```

Search package names at [search.nixos.org](https://search.nixos.org/packages).

**Removing a feature:** delete its import line from
`hosts/YOURHOSTNAME/YOURHOSTNAME.nix` and rebuild. Every feature is one
line.

## Already running Linux? Try it in a VM first

On an existing NixOS machine you can test-drive without installing
anything:

```
nix run github:jspadgett/space-elevator
cd nixos-config
nixos-rebuild build-vm --flake .#YOURHOSTNAME
./result/bin/run-YOURHOSTNAME-vm
```

A window opens with your complete desktop running inside it. Like it?
The same config installs for real.

## Getting help

- [NixOS Discourse](https://discourse.nixos.org/) — friendly forum
- [NixOS Wiki](https://wiki.nixos.org/) — practical how-tos
- [NixOS Manual](https://nixos.org/manual/nixos/stable/) — the full reference
- Something wrong with Space Elevator itself? [Open an issue](https://github.com/jspadgett/space-elevator/issues).
