# modules/desktop/theming.nix
# Catppuccin system-wide theming — part of the look, so it is on by
# default wherever there is a desktop.
#
# This is the one feature that needs something from outside the
# repository, because the theme ships as its own flake. Generated
# configs have it wired up already; to add it to a config that
# doesn't, flake.nix needs the input:
#
#   inputs.catppuccin.url = "github:catppuccin/nix/release-26.05";
#
# and the host needs its module, alongside ../../modules in
# hosts/<name>/<name>.nix:
#
#   inputs.catppuccin.nixosModules.catppuccin
#
# Rather than importing that conditionally (which the module system
# won't do — imports can't depend on configuration), this module checks
# whether the option tree has a `catppuccin` branch and says so plainly
# if it doesn't.
{
  config,
  options,
  lib,
  ...
}:
let
  cfg = config.spaceElevator.desktop.theming;
  hasModule = options ? catppuccin;
in
{
  options.spaceElevator.desktop.theming = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.desktop.enable;
      defaultText = lib.literalExpression "config.spaceElevator.desktop.enable";
      description = ''
        Catppuccin theming across the system. On by default with any
        desktop; needs the catppuccin flake input, and says so (as a
        build-time warning) if it is missing.
      '';
    };

    flavor = lib.mkOption {
      type = lib.types.enum [
        "latte"
        "frappe"
        "macchiato"
        "mocha"
      ];
      default = "mocha";
      description = "Catppuccin flavor — latte is the light one, mocha the darkest.";
    };

    accent = lib.mkOption {
      type = lib.types.enum [
        "rosewater"
        "flamingo"
        "pink"
        "mauve"
        "red"
        "maroon"
        "peach"
        "yellow"
        "green"
        "teal"
        "sky"
        "sapphire"
        "blue"
        "lavender"
      ];
      default = "mauve";
      description = "Catppuccin accent color.";
    };
  };

  config = lib.mkIf cfg.enable (
    {
      # A warning rather than an assertion: theming is on by default,
      # and a missing theme should leave you with a plain-looking
      # desktop, not a system that refuses to build.
      warnings = lib.optional (!hasModule) ''
        spaceElevator.desktop.theming is enabled but the catppuccin
        flake input is missing, so the system will build unthemed.
        In flake.nix:

          inputs.catppuccin.url = "github:catppuccin/nix/release-26.05";

        and in hosts/<name>/<name>.nix, next to ../../modules:

          inputs.catppuccin.nixosModules.catppuccin

        Or turn theming off: spaceElevator.desktop.theming.enable = false;
      '';
    }
    // lib.optionalAttrs hasModule {
      catppuccin = {
        enable = true;
        inherit (cfg) flavor accent;
      };
    }
  );
}
