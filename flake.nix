{
  description = "Space Elevator - opinionated NixOS desktop generator. From bare metal to orbit.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      # What a generated config follows; see release.nix. nixosRelease
      # has to be written down rather than read from nixpkgs: a config
      # makes this flake's nixpkgs follow its own, so nixpkgs would
      # report the user's release back to them.
      # checks.release-matches-nixpkgs keeps it honest.
      inherit (import ./release.nix) version nixosRelease;

      # Empty for a dirty tree. Where it is set, the wizard and the
      # upgrade lock the config to exactly these modules rather than
      # whatever the stable branch says by the time they run.
      selfRev = self.rev or "";

      mkScaffold = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.writeShellApplication {
          name = "space-elevator";
          runtimeInputs = with pkgs; [ gum coreutils gnused gnugrep git pciutils mkpasswd ];
          excludeShellChecks = [ "SC2016" ];
          text = ''
            MODULE_SOURCE="${./modules}"
            SE_NIXPKGS_REV="${nixpkgs.rev or ""}"
            SE_SELF_REV="${selfRev}"
            SE_NIXOS_RELEASE="${nixosRelease}"
            ${builtins.readFile ./scaffold.sh}
          '';
        };
      # Upgrades a machine that already runs a generated config. It
      # carries the scaffold in its closure and calls it, so the whole
      # thing works from one `nix run`.
      mkUpgrade = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.writeShellApplication {
          name = "space-elevator-upgrade";
          runtimeInputs = with pkgs; [ gum coreutils gnused gnugrep gawk diffutils findutils git ];
          excludeShellChecks = [ "SC2016" ];
          text = ''
            SCAFFOLD_BIN="${mkScaffold system}/bin/space-elevator"
            MODULE_SOURCE="${./modules}"
            SE_SELF_REV="${selfRev}"
            ${builtins.readFile ./upgrade.sh}
          '';
        };
      # Updates a machine in place: Space Elevator to its newest
      # release, nixpkgs (across a NixOS release when the modules
      # moved to one), every other input; then builds, shows the
      # difference and switches. A config's own update.sh runs this
      # from the stable branch, so improvements to updating ship with
      # releases instead of living in a file nobody regenerates.
      # nix and nixos-rebuild come from the system it runs on.
      mkUpdate = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.writeShellApplication {
          name = "space-elevator-update";
          runtimeInputs = with pkgs; [ gum coreutils gnused gnugrep diffutils findutils git nvd ];
          excludeShellChecks = [ "SC2016" ];
          text = builtins.readFile ./update.sh;
        };
    in
    {
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${mkScaffold system}/bin/space-elevator";
        };
        upgrade = {
          type = "app";
          program = "${mkUpgrade system}/bin/space-elevator-upgrade";
        };
        update = {
          type = "app";
          program = "${mkUpdate system}/bin/space-elevator-update";
        };
      });

      packages = forAllSystems (system: {
        default = mkScaffold system;
        space-elevator = mkScaffold system;
        upgrade = mkUpgrade system;
        update = mkUpdate system;
      });

      # Read by `update` out of a config's locked copy of this flake.
      lib = { inherit version nixosRelease; };

      # The module set on its own, for anyone who would rather point a
      # flake input at it than vendor a copy:
      #
      #   imports = [ inputs.space-elevator.nixosModules.default ];
      #   spaceElevator = { enable = true; desktop.plasma.enable = true; };
      #
      # Importing it turns nothing on by itself.
      nixosModules = rec {
        space-elevator = ./modules;
        default = space-elevator;
      };

      # Evaluation tests for the module set — `nix flake check`.
      # x86_64 only: they evaluate whole desktops, and a few packages
      # (Steam, the NVIDIA driver) don't exist on aarch64 at all.
      checks.x86_64-linux = import ./tests/checks.nix {
        inherit nixpkgs;
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      } // {
        # nixosRelease is what every config gets pinned to; a lock bump
        # to the next release without it would send users nowhere.
        release-matches-nixpkgs =
          let actual = nixpkgs.lib.trivial.release; in
          assert nixpkgs.lib.assertMsg (actual == nixosRelease)
            "flake.nix says nixosRelease = \"${nixosRelease}\" but flake.lock has nixpkgs ${actual}";
          nixpkgs.legacyPackages.x86_64-linux.emptyFile;
      };

      nixosConfigurations.space-elevator-iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { space-elevator = mkScaffold "x86_64-linux"; };
        modules = [ ./iso/iso.nix ];
      };
    };
}
