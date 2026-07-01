# modules/features/gpgagent.nix
# GnuPG agent with SSH support
{ ... }:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
}
