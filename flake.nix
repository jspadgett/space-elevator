{
  description = "Space Elevator - opinionated NixOS desktop generator. From bare metal to orbit.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      mkScaffold = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.writeShellApplication {
          name = "space-elevator";
          runtimeInputs = with pkgs; [ gum coreutils gnused gnugrep git pciutils mkpasswd ];
          excludeShellChecks = [ "SC2016" ];
          text = ''
            MODULE_SOURCE="${./modules}"
            SE_NIXPKGS_REV="${nixpkgs.rev or ""}"
            SE_ZONEINFO="${pkgs.tzdata}/share/zoneinfo"
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
          runtimeInputs = with pkgs; [ gum coreutils gnused gnugrep diffutils findutils git ];
          excludeShellChecks = [ "SC2016" ];
          text = ''
            SCAFFOLD_BIN="${mkScaffold system}/bin/space-elevator"
            SE_ZONEINFO="${pkgs.tzdata}/share/zoneinfo"
            ${builtins.readFile ./upgrade.sh}
          '';
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
      });

      packages = forAllSystems (system: {
        default = mkScaffold system;
        space-elevator = mkScaffold system;
        upgrade = mkUpgrade system;
      });

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
      };

      nixosConfigurations.space-elevator-iso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { space-elevator = mkScaffold "x86_64-linux"; };
        modules = [ ./iso/iso.nix ];
      };
    };
}
