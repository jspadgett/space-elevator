# modules/features/shell-zsh.nix
# Zsh as default shell with autosuggestions, syntax highlighting, starship prompt
{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };
  programs.starship.enable = true;
  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];
}
