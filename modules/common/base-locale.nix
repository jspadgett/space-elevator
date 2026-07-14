# modules/common/base-locale.nix
# Locale and keyboard layout, read from the wizard's answers
# (spaceElevator.* in hosts/<name>/settings.nix).
{ config, ... }:
let
  se = config.spaceElevator;
in
{
  i18n.defaultLocale = se.locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = se.locale;
    LC_IDENTIFICATION = se.locale;
    LC_MEASUREMENT = se.locale;
    LC_MONETARY = se.locale;
    LC_NAME = se.locale;
    LC_NUMERIC = se.locale;
    LC_PAPER = se.locale;
    LC_TELEPHONE = se.locale;
    LC_TIME = se.locale;
  };

  # Keyboard layout for graphical sessions; the console follows it too,
  # so the login screen and TTYs match what's printed on the keys.
  services.xserver.xkb.layout = se.keyboard.layout;
  console.useXkbConfig = true;
}
