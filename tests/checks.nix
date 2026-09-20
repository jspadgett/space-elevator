# tests/checks.nix — evaluation tests for the module set.
#
# Run them all with `nix flake check`, or one at a time:
#   nix build .#checks.x86_64-linux.desktop-plasma
#
# Two kinds of test live here:
#
#   evalCheck  — the configuration evaluates end to end, which means
#                every module it touches type-checks AND every
#                assertion passes (building `toplevel` is what makes
#                assertions fire).
#   expect     — a specific fact about the evaluated config, so we
#                catch a feature quietly turning itself off.
#   expectAssertion — a *deliberately* broken config trips the
#                assertion we wrote for it, with a useful message.
#
# Nothing here builds a system: the derivation path is evaluated and
# then stripped of its string context, so the check is pure evaluation.
{
  pkgs,
  nixpkgs,
  system,
}:
let
  inherit (nixpkgs) lib;

  # Enough hardware to make nixosSystem evaluate; no disk is touched.
  stub = {
    fileSystems."/" = {
      device = "/dev/vda1";
      fsType = "ext4";
    };
    boot.loader.grub.device = "/dev/vda";
    system.stateVersion = "26.05";
  };

  eval =
    module:
    lib.nixosSystem {
      inherit system;
      modules = [
        ../modules
        stub
        module
      ];
    };

  # Forces the whole system to evaluate — assertions included —
  # without pulling the build into the check's dependencies.
  evalCheck =
    name: module:
    pkgs.runCommand "se-check-${name}" { } ''
      echo ${builtins.unsafeDiscardStringContext (eval module).config.system.build.toplevel.drvPath} > $out
    '';

  # Failure output goes through a file: assertion messages contain
  # backticks and quotes, and interpolating those into a shell script
  # would have the builder try to run them.
  report =
    name: ok: text:
    let
      message = pkgs.writeText "se-check-${name}-message" text;
    in
    pkgs.runCommand "se-check-${name}" { } (
      if ok then
        "cp ${message} $out"
      else
        ''
          cat ${message} >&2
          exit 1
        ''
    );

  # Assertion messages are written as wrapped prose, so compare them
  # with their line breaks and runs of spaces flattened.
  squash =
    s:
    lib.concatStringsSep " " (
      lib.filter (piece: builtins.isString piece && piece != "") (builtins.split "[[:space:]]+" s)
    );

  expect =
    name: module: description: predicate:
    report name (predicate (eval module).config) "FAILED: ${description}";

  # For values a module rejects outright (an option type refusing a
  # malformed value) rather than reporting through an assertion.
  expectRejected =
    name: module: accessor: description:
    let
      attempt = builtins.tryEval (builtins.deepSeq (accessor (eval module).config) null);
    in
    report name (!attempt.success) "FAILED: ${description} — the value was accepted instead.";

  expectWarning =
    name: module: fragment:
    let
      warnings = (eval module).config.warnings;
      hit = lib.any (w: lib.hasInfix fragment (squash w)) warnings;
    in
    report name hit ''
      FAILED: expected a warning mentioning "${fragment}".
      Warnings were:
      ${lib.concatMapStringsSep "\n" (w: "  - ${squash w}") warnings}
    '';

  failedAssertions =
    module: map (a: a.message) (lib.filter (a: !a.assertion) (eval module).config.assertions);

  expectAssertion =
    name: module: fragment:
    let
      messages = failedAssertions module;
      hit = lib.any (m: lib.hasInfix fragment (squash m)) messages;
    in
    report name hit ''
      FAILED: expected an assertion mentioning "${fragment}".
      Failing assertions were:
      ${lib.concatMapStringsSep "\n" (m: "  - ${squash m}") messages}
    '';

  desktop = de: {
    spaceElevator = {
      enable = true;
      user.name = "alice";
      desktop.${de}.enable = true;
    };
    users.users.alice.isNormalUser = true;
  };
in
{
  # ── Importing the module set does nothing on its own ──────────────
  inert-import = expect "inert-import" { } "importing modules/ without spaceElevator.enable changes nothing" (
    c:
    !c.services.pipewire.enable
    && !c.networking.networkmanager.enable
    && !c.services.earlyoom.enable
    && !c.hardware.bluetooth.enable
  );

  # ── The baseline, with and without a desktop ──────────────────────
  baseline-headless = evalCheck "baseline-headless" { spaceElevator.enable = true; };

  baseline-headless-has-no-desktop =
    expect "baseline-headless-has-no-desktop" { spaceElevator.enable = true; }
      "a desktop-free baseline skips the desktop plumbing, and the things that follow a desktop"
      (
        c:
        c.services.earlyoom.enable
        && !c.services.pipewire.enable
        && !c.services.printing.enable
        && !c.programs.steam.enable
        && !c.programs.firefox.enable
      );

  # ── Standard equipment: no question asked, still one line to drop ─
  gaming-is-standard =
    expect "gaming-is-standard" (desktop "plasma")
      "a desktop comes with Steam, GameMode and MangoHud, unasked"
      (c: c.programs.steam.enable && c.programs.gamemode.enable && c.programs.gamescope.enable);

  gaming-full-kit =
    expect "gaming-full-kit" (desktop "plasma")
      "the gaming baseline covers protontricks, controllers, launchers and the sysctls"
      (
        c:
        c.programs.steam.protontricks.enable
        && c.hardware.xpadneo.enable
        && c.hardware.xone.enable
        && c.boot.kernel.sysctl."vm.max_map_count" == 2147483642
        && c.boot.kernel.sysctl."kernel.split_lock_mitigate" == 0
        && lib.any (p: (p.pname or "") == "heroic") c.environment.systemPackages
        && lib.any (p: (p.pname or "") == "lutris") c.environment.systemPackages
      );

  gaming-off-is-off =
    expect "gaming-off-is-off"
      {
        spaceElevator = {
          enable = true;
          desktop.gnome.enable = true;
          gaming.enable = false;
        };
      }
      "declining gaming takes the controllers, launchers and sysctls with it"
      (
        c:
        !c.hardware.xpadneo.enable
        && !c.hardware.xone.enable
        && !(c.boot.kernel.sysctl ? "kernel.split_lock_mitigate")
        && !lib.any (p: (p.pname or "") == "heroic") c.environment.systemPackages
      );

  gamescope-session-is-opt-in =
    expect "gamescope-session-is-opt-in" (desktop "plasma")
      "the Big Picture session stays off unless asked for"
      (c: !c.programs.steam.gamescopeSession.enable);

  gamescope-session-adds-a-login-option = evalCheck "gamescope-session-adds-a-login-option" {
    spaceElevator = {
      enable = true;
      user.name = "alice";
      desktop.plasma.enable = true;
      gaming.steam.gamescopeSession = true;
    };
    users.users.alice.isNormalUser = true;
  };

  streaming-and-rgb-are-opt-in =
    expect "streaming-and-rgb-are-opt-in" (desktop "gnome")
      "Sunshine and OpenRGB stay off until asked for"
      (c: !c.services.sunshine.enable && !c.services.hardware.openrgb.enable);

  gaming-extras = evalCheck "gaming-extras" {
    spaceElevator = {
      enable = true;
      user.name = "alice";
      desktop.gnome.enable = true;
      gaming = {
        streaming.enable = true;
        rgb.enable = true;
        controllers.mice = true;
        steam.gamescopeSession = true;
      };
    };
    users.users.alice.isNormalUser = true;
  };

  vesktop-is-standard =
    expect "vesktop-is-standard" (desktop "gnome")
      "voice chat comes with the desktop"
      (c: lib.any (p: (p.pname or "") == "vesktop") c.environment.systemPackages);

  # ── Kernel choice ────────────────────────────────────────────────
  kernel-defaults-to-latest =
    expect "kernel-defaults-to-latest" { spaceElevator.enable = true; }
      "the baseline runs the newest mainline kernel"
      (c: c.spaceElevator.base.kernel == "latest");

  kernel-zen = evalCheck "kernel-zen" {
    spaceElevator = {
      enable = true;
      base.kernel = "zen";
    };
  };

  kernel-xanmod = evalCheck "kernel-xanmod" {
    spaceElevator = {
      enable = true;
      base.kernel = "xanmod";
    };
  };

  nvidia-moves-the-kernel-default =
    expect "nvidia-moves-the-kernel-default"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia.enable = true;
        };
      }
      "the NVIDIA driver pins the release kernel rather than mainline"
      (c: c.spaceElevator.base.kernel == "default");

  nvidia-kernel-override-warns =
    expectWarning "nvidia-kernel-override-warns"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia.enable = true;
          base.kernel = "zen";
        };
      }
      "this is the pairing that breaks";

  nvidia-kernel-override-is-honoured = evalCheck "nvidia-kernel-override-is-honoured" {
    spaceElevator = {
      enable = true;
      gpu.nvidia.enable = true;
      base.kernel = "zen";
    };
  };

  gaming-can-be-declined =
    expect "gaming-can-be-declined"
      {
        spaceElevator = {
          enable = true;
          desktop.gnome.enable = true;
          gaming.enable = false;
        };
      }
      "gaming.enable = false leaves a plain desktop"
      (c: !c.programs.steam.enable && !c.programs.gamemode.enable);

  firefox-is-standard =
    expect "firefox-is-standard" (desktop "hyprland")
      "a desktop comes with a browser"
      (c: c.programs.firefox.enable);

  firefox-can-be-declined =
    expect "firefox-can-be-declined"
      {
        spaceElevator = {
          enable = true;
          desktop.gnome.enable = true;
          desktop.packages.firefox = false;
        };
      }
      "desktop.packages.firefox = false leaves the browser out without taking the app set with it"
      (c: !c.programs.firefox.enable && lib.any (p: (p.pname or "") == "kitty") c.environment.systemPackages);

  theming-is-standard =
    expect "theming-is-standard" (desktop "cosmic")
      "a desktop is themed unasked"
      (c: c.spaceElevator.desktop.theming.enable);

  # ── Desktops, each with the shared plumbing behind it ─────────────
  desktop-plasma = evalCheck "desktop-plasma" (desktop "plasma");
  desktop-gnome = evalCheck "desktop-gnome" (desktop "gnome");
  desktop-cosmic = evalCheck "desktop-cosmic" (desktop "cosmic");
  desktop-hyprland = evalCheck "desktop-hyprland" (desktop "hyprland");

  desktop-pulls-in-plumbing = expect "desktop-pulls-in-plumbing" (desktop "gnome")
    "enabling a desktop turns on audio, printing, fonts and Flatpak"
    (
      c:
      c.services.pipewire.enable
      && c.services.printing.enable
      && c.services.flatpak.enable
      && c.services.udisks2.enable
      && c.fonts.packages != [ ]
    );

  plumbing-is-overridable =
    expect "plumbing-is-overridable"
      {
        spaceElevator = {
          enable = true;
          desktop.gnome.enable = true;
          desktop.bluetooth.enable = false;
        };
      }
      "a desktop's plumbing can still be switched off piece by piece"
      # The Blueman applet is ours to withdraw; hardware.bluetooth
      # itself is not, because GNOME switches that on for its own
      # settings panel regardless of what we do.
      (c: c.services.pipewire.enable && !c.services.blueman.enable);

  kdeconnect-follows-plasma =
    expect "kdeconnect-follows-plasma" (desktop "plasma")
      "KDE Connect comes with the Plasma flavor"
      (c: c.programs.kdeconnect.enable);

  kdeconnect-stays-off-elsewhere =
    expect "kdeconnect-stays-off-elsewhere" (desktop "gnome")
      "KDE Connect does not follow other desktops"
      (c: !c.programs.kdeconnect.enable);

  one-desktop-at-a-time =
    expectAssertion "one-desktop-at-a-time"
      {
        spaceElevator = {
          enable = true;
          desktop.plasma.enable = true;
          desktop.gnome.enable = true;
        };
      }
      "pick one desktop environment";

  # ── Locale ────────────────────────────────────────────────────────
  locale-applies =
    expect "locale-applies"
      {
        spaceElevator = {
          enable = true;
          locale = {
            defaultLocale = "de_DE.UTF-8";
            keyboardLayout = "de";
          };
        };
      }
      "the locale options reach i18n and XKB"
      (
        c:
        c.i18n.defaultLocale == "de_DE.UTF-8"
        && c.i18n.extraLocaleSettings.LC_TIME == "de_DE.UTF-8"
        && c.services.xserver.xkb.layout == "de"
      );

  # ── GPUs ──────────────────────────────────────────────────────────
  gpu-amd = evalCheck "gpu-amd" { spaceElevator = { enable = true; gpu.amd.enable = true; }; };
  gpu-intel = evalCheck "gpu-intel" { spaceElevator = { enable = true; gpu.intel.enable = true; }; };
  gpu-nvidia = evalCheck "gpu-nvidia" { spaceElevator = { enable = true; gpu.nvidia.enable = true; }; };

  gpu-nvidia-prime = evalCheck "gpu-nvidia-prime" {
    spaceElevator = {
      enable = true;
      gpu.nvidia = {
        enable = true;
        prime = {
          enable = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };
    };
  };

  gpu-nvidia-prime-powers-down =
    expect "gpu-nvidia-prime-powers-down"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia = {
            enable = true;
            prime = {
              enable = true;
              amdgpuBusId = "PCI:5:0:0";
              nvidiaBusId = "PCI:1:0:0";
            };
          };
        };
      }
      "PRIME offload implies runtime D3 and the offload command"
      (
        c:
        c.hardware.nvidia.powerManagement.finegrained
        && c.hardware.nvidia.prime.offload.enable
        && c.hardware.nvidia.prime.amdgpuBusId == "PCI:5:0:0"
      );

  gpu-nvidia-legacy = evalCheck "gpu-nvidia-legacy" {
    spaceElevator = {
      enable = true;
      gpu.nvidia = {
        enable = true;
        driver = "legacy_470";
      };
    };
  };

  gpu-prime-needs-bus-ids =
    expectAssertion "gpu-prime-needs-bus-ids"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia = {
            enable = true;
            prime.enable = true;
          };
        };
      }
      "needs bus IDs";

  gpu-prime-rejects-hex-bus-ids =
    expectRejected "gpu-prime-rejects-hex-bus-ids"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia = {
            enable = true;
            prime = {
              enable = true;
              intelBusId = "PCI:0:2:0";
              nvidiaBusId = "0a:00.0"; # what lspci prints, not what NixOS wants
            };
          };
        };
      }
      (c: c.hardware.nvidia.prime.nvidiaBusId)
      "a hex bus ID is rejected by the option type";

  gpu-prime-rejects-two-igpus =
    expectAssertion "gpu-prime-rejects-two-igpus"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia = {
            enable = true;
            prime = {
              enable = true;
              intelBusId = "PCI:0:2:0";
              amdgpuBusId = "PCI:5:0:0";
              nvidiaBusId = "PCI:1:0:0";
            };
          };
        };
      }
      "never both";

  gpu-finegrained-needs-prime =
    expectAssertion "gpu-finegrained-needs-prime"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia = {
            enable = true;
            powerManagement.finegrained = true;
          };
        };
      }
      "requires";

  gpu-legacy-rejects-open-modules =
    expectAssertion "gpu-legacy-rejects-open-modules"
      {
        spaceElevator = {
          enable = true;
          gpu.nvidia = {
            enable = true;
            driver = "legacy_470";
            open = true;
          };
        };
      }
      "open kernel modules do not support the legacy_470 branch";

  gpu-amd-and-nvidia-conflict =
    expectAssertion "gpu-amd-and-nvidia-conflict"
      {
        spaceElevator = {
          enable = true;
          gpu.amd.enable = true;
          gpu.nvidia.enable = true;
        };
      }
      "are both enabled";

  # ── Flavors ───────────────────────────────────────────────────────
  flavor-gaming = evalCheck "flavor-gaming" {
    spaceElevator = {
      enable = true;
      user.name = "alice";
      gaming.enable = true;
    };
    users.users.alice.isNormalUser = true;
  };

  gaming-rollup-and-override =
    expect "gaming-rollup-and-override"
      {
        spaceElevator = {
          enable = true;
          user.name = "alice";
          gaming.enable = true;
          gaming.gamemode.enable = false;
        };
        users.users.alice.isNormalUser = true;
      }
      "the gaming flavor turns on its parts, and each part can be overridden"
      (c: c.programs.steam.enable && !c.programs.gamemode.enable);

  gaming-puts-user-in-group =
    expect "gaming-puts-user-in-group"
      {
        spaceElevator = {
          enable = true;
          user.name = "alice";
          gaming.enable = true;
        };
        users.users.alice.isNormalUser = true;
      }
      "spaceElevator.user.name lands in the gamemode group"
      (c: lib.elem "gamemode" c.users.users.alice.extraGroups);

  flavor-development = evalCheck "flavor-development" {
    spaceElevator = {
      enable = true;
      user.name = "alice";
      development.enable = true;
    };
    users.users.alice.isNormalUser = true;
  };

  development-rollup =
    expect "development-rollup"
      {
        spaceElevator = {
          enable = true;
          user.name = "alice";
          development.enable = true;
        };
        users.users.alice.isNormalUser = true;
      }
      "the development flavor brings Docker, libvirt and group membership"
      (
        c:
        c.virtualisation.docker.enable
        && c.virtualisation.libvirtd.enable
        && lib.elem "libvirtd" c.users.users.alice.extraGroups
      );

  # Theming is on by default, so a missing input must not be fatal:
  # you get a plain desktop and a warning that says how to fix it.
  theming-without-input-warns =
    expectWarning "theming-without-input-warns"
      {
        spaceElevator = {
          enable = true;
          desktop.theming.enable = true;
        };
      }
      "catppuccin flake input is missing";

  theming-without-input-still-builds = evalCheck "theming-without-input-still-builds" {
    spaceElevator = {
      enable = true;
      desktop.theming.enable = true;
    };
  };

  # ── Laptop ────────────────────────────────────────────────────────
  laptop-tlp = evalCheck "laptop-tlp" {
    spaceElevator = {
      enable = true;
      tuning.tlp.enable = true;
    };
  };

  tlp-thresholds-are-optional =
    expect "tlp-thresholds-are-optional"
      {
        spaceElevator = {
          enable = true;
          tuning.tlp = {
            enable = true;
            chargeThresholds = null;
          };
        };
      }
      "charge thresholds can be dropped for batteries that lack them"
      (c: !(c.services.tlp.settings ? START_CHARGE_THRESH_BAT0) && !c.services.power-profiles-daemon.enable);

  # ── Housekeeping options actually reach their services ────────────
  tuning-options-apply =
    expect "tuning-options-apply"
      {
        spaceElevator = {
          enable = true;
          tuning.nixGc.keepDays = 30;
          tuning.zram.memoryPercent = 25;
          network.firewall.allowedTCPPorts = [ 8080 ];
        };
      }
      "tuning and firewall options reach the underlying services"
      (
        c:
        c.nix.gc.options == "--delete-older-than 30d"
        && c.zramSwap.memoryPercent == 25
        && lib.elem 8080 c.networking.firewall.allowedTCPPorts
      );

  tuning-can-be-switched-off =
    expect "tuning-can-be-switched-off"
      {
        spaceElevator = {
          enable = true;
          tuning.enable = false;
        };
      }
      "tuning.enable = false silences the whole housekeeping group"
      (c: !c.services.earlyoom.enable && !c.nix.gc.automatic && !c.zramSwap.enable);

  # ── The full house: everything the wizard can select at once ──────
  everything = evalCheck "everything" {
    spaceElevator = {
      enable = true;
      user.name = "alice";
      desktop.plasma.enable = true;
      desktop.kdeconnect.enable = true;
      gpu.nvidia = {
        enable = true;
        prime = {
          enable = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };
      gaming.enable = true;
      development.enable = true;
      tuning.tlp.enable = true;
    };
    users.users.alice.isNormalUser = true;
  };
}
