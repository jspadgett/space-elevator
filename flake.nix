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
            ${builtins.readFile ./scaffold.sh}
          '';
        };
    in
    {
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${mkScaffold system}/bin/space-elevator";
        };
      });

      packages = forAllSystems (system: {
        default = mkScaffold system;
      });
    };
}
