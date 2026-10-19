# Developing

## Layout

| Path | What it is |
|---|---|
| `modules/` | The module set, one directory per category |
| `scaffold.sh` | The installer wizard; writes a config |
| `update.sh` | The updater a config's `update.sh` runs |
| `upgrade.sh` | Moves older configs onto the current layout |
| `iso/` | The installer ISO |
| `release.nix` | The version, and the NixOS release it targets |
| `tests/` | `run.sh` (shell harness) and `checks.nix` (`nix flake check`) |

You need Nix with flakes enabled.

## Running the wizard without prompts

Set `SE_NONINTERACTIVE=1` plus any `SE_*` variables to generate a
config without questions. The full list is in the header of
`scaffold.sh`. For example:

```sh
SE_NONINTERACTIVE=1 SE_HOSTNAME=test SE_USERNAME=me SE_GPU=AMD \
  SE_DE=GNOME SE_OUTDIR=./out bash scaffold.sh
```

A generated config takes the modules from the `stable` branch. To
evaluate it against your checkout instead:

```sh
cd out
nix eval --override-input space-elevator "path:$(dirname "$PWD")" \
  .#nixosConfigurations.test.config.system.build.vm.drvPath
```

## Tests

| What | How |
|---|---|
| The wizard writes the right switches | `bash tests/run.sh` generates a config for every desktop, GPU and extra, and checks the output |
| Updates and upgrades do what they say | `bash tests/run.sh` runs the upgrade on every layout that has shipped, and the updater against local stand-ins for GitHub |
| The modules work | `nix flake check` runs [tests/checks.nix](../tests/checks.nix): every feature combination evaluates, importing the set turns nothing on, and each assertion fires when it should |
| Generated configs build | CI evaluates the VM derivation for each desktop and GPU |
| The ISO builds | CI evaluates the ISO derivation |

## Adding a module

1. Add a `.nix` file to the right `modules/` category. Declare
   `options.spaceElevator.<category>.<name>.enable` and wrap the
   config in `lib.mkIf`.
2. Import it from that category's `default.nix`.

The option path mirrors the directory. A feature that should follow
its category's big switch takes
`default = config.spaceElevator.<category>.enable;`. A module that
needs the primary user's name reads `config.spaceElevator.user.name`.
Keep it to one feature per file, with no dependencies on other
modules.

Add a test in `tests/checks.nix`: an `evalCheck` at minimum, and an
`expect` if the feature has behavior worth pinning down.

## Releasing

Installed machines follow the `stable` branch, so it only moves through
[the release workflow](../.github/workflows/release.yml):

1. On main, bump `version` in `release.nix`. When `flake.lock` moves
   to a new NixOS release, bump `nixosRelease` too; `nix flake check`
   fails if the two disagree.
2. `git tag v<version> && git push origin v<version>`

The workflow builds the ISO and attaches it to the release, runs the
full CI suite on the tag, checks the tag matches `release.nix` and is
on main, then moves `stable` to it.

To pull a bad release, run the workflow by hand with the previous tag
and "rollback" ticked. Machines that already updated go back on their
next `update.sh`.

## Contributing

Issues and pull requests are welcome.
