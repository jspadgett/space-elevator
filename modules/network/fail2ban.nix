# modules/features/fail2ban.nix
# Bans IPs after repeated failed SSH logins. Pairs with ssh-hardened.nix.
{ ... }:
{
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
    };
  };
}
