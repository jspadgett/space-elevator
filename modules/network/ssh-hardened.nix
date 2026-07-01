# modules/features/ssh-hardened.nix
# OpenSSH with sane hardening: key-only auth, no root login.
# Make sure your SSH public key is in users.users.<name>.openssh.authorizedKeys
# BEFORE enabling this, or you will lock yourself out of remote access.
{ ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };
}
