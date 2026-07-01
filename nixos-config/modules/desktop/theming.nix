# modules/desktop/theming.nix
# Catppuccin system-wide theming. Requires the catppuccin flake input.
{ inputs, ... }:
{
  imports = [ inputs.catppuccin.nixosModules.catppuccin ];
  catppuccin = {
    enable = true;
    flavor = "mocha";
    accent = "mauve";
  };
}
