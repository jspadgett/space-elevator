# modules/common/locale.nix
# Locale and keyboard layout. The wizard fills these in from the
# machine it runs on; change them here any time.
{ config, lib, ... }:
let
  cfg = config.spaceElevator.locale;
in
{
  options.spaceElevator.locale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.spaceElevator.enable;
      defaultText = lib.literalExpression "config.spaceElevator.enable";
      description = ''
        Apply the locale and keyboard layout below. Turn this off to
        manage i18n and XKB settings by hand.
      '';
    };

    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      example = "de_DE.UTF-8";
      description = ''
        System locale, used for both `i18n.defaultLocale` and the
        regional `LC_*` settings (dates, paper size, currency).
      '';
    };

    keyboardLayout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      example = "de";
      description = ''
        XKB keyboard layout for graphical sessions. The console follows
        it too, so the login screen and TTYs match what's printed on
        the keys.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    i18n.defaultLocale = cfg.defaultLocale;
    i18n.extraLocaleSettings = {
      LC_ADDRESS = cfg.defaultLocale;
      LC_IDENTIFICATION = cfg.defaultLocale;
      LC_MEASUREMENT = cfg.defaultLocale;
      LC_MONETARY = cfg.defaultLocale;
      LC_NAME = cfg.defaultLocale;
      LC_NUMERIC = cfg.defaultLocale;
      LC_PAPER = cfg.defaultLocale;
      LC_TELEPHONE = cfg.defaultLocale;
      LC_TIME = cfg.defaultLocale;
    };

    services.xserver.xkb.layout = cfg.keyboardLayout;
    console.useXkbConfig = true;
  };
}
