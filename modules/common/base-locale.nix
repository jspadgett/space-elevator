# modules/common/base-locale.nix
# Locale and keyboard layout, filled in by the wizard.
{ ... }:
{
  i18n.defaultLocale = "@LOCALE@";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "@LOCALE@";
    LC_IDENTIFICATION = "@LOCALE@";
    LC_MEASUREMENT = "@LOCALE@";
    LC_MONETARY = "@LOCALE@";
    LC_NAME = "@LOCALE@";
    LC_NUMERIC = "@LOCALE@";
    LC_PAPER = "@LOCALE@";
    LC_TELEPHONE = "@LOCALE@";
    LC_TIME = "@LOCALE@";
  };

  # Keyboard layout for graphical sessions; the console follows it too,
  # so the login screen and TTYs match what's printed on the keys.
  services.xserver.xkb.layout = "@KB_LAYOUT@";
  console.useXkbConfig = true;
}
