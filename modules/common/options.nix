# modules/common/options.nix
# Declares the spaceElevator.* options namespace. The wizard writes the
# answers into hosts/<name>/settings.nix; modules read them from here.
# This file only declares that the settings exist — it sets nothing.
{ lib, ... }:
{
  options.spaceElevator = {
    user.name = lib.mkOption {
      type = lib.types.str;
      description = "Primary user account name, set by the wizard.";
      example = "alice";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "System locale, set by the wizard.";
    };

    keyboard.layout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "XKB keyboard layout, set by the wizard.";
      example = "de";
    };
  };
}
