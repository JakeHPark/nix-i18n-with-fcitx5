# Nix i18n with Fcitx5

I'm trilingual. I need to be able to type in at least English, French and Korean. I also like 24-hour time. None of this is obvious at all to configure. I'm uploading my solution here in case some other polyglot degenerate also happens to use NixOS + KDE + Wayland. `Meta+Space` to rotate between input languages. You're welcome.

```nix
i18n = {
  defaultLocale = "en_AU.UTF-8";
  # 24-hour time.
  extraLocaleSettings."LC_TIME" = "C.UTF-8";

  inputMethod = {
    enable = true;
    # Fcitx has better Wayland compatibility than IBus.
    type = "fcitx5";

    fcitx5 = {
      waylandFrontend = true;
      # Ignore user configuration in `~/.config` to maintain full declarative status.
      ignoreUserConfig = true;

      addons = with pkgs; [
        fcitx5-hangul
        fcitx5-gtk
      ];

      settings = {
        globalOptions = {
          Hotkey = {
            EnumerateWithTriggerKeys = false;
            EnumerateSkipFirst = false;
            ModifierOnlyKeyTimeout = 250;
          };

          # Meta+Space: cycle forward through English -> English Intl -> Hangul.
          "Hotkey/EnumerateForwardKeys"."0" = "Super+space";

          # Optional reverse cycle.
          "Hotkey/EnumerateBackwardKeys"."0" = "Shift+Super+space";

          # Keep trigger empty so Ctrl+Space/Hangul keys don't create a second switching regime.
          "Hotkey/TriggerKeys" = { };
          "Hotkey/AltTriggerKeys" = { };

          Behavior = {
            ActiveByDefault = false;
            ShareInputState = "No";
            PreeditEnabledByDefault = true;
            ShowInputMethodInformation = true;
            showInputMethodInformationWhenFocusIn = false;
            CompactInputMethodInformation = true;
            ShowFirstInputMethodInformation = true;
            DefaultPageSize = 5;
            OverrideXkbOption = false;
            PreloadInputMethod = true;
          };
        };

        inputMethod = {
          GroupOrder."0" = "Default";

          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "keyboard-us";
          };

          # Plain English.
          "Groups/0/Items/0".Name = "keyboard-us";

          # English International with dead keys:
          # ' + e -> é, ` + e -> è, ^ + e -> ê, etc.
          "Groups/0/Items/1".Name = "keyboard-us-intl";

          # Korean via fcitx5-hangul.
          "Groups/0/Items/2".Name = "hangul";
        };
      };
    };
  };
};
```

Also, GLFW/kitty needs this set. Yes, `ibus` [even with](https://www.fcitx-im.org/wiki/Setup_Fcitx_5#Other_less_common_setup) Fcitx.

```nix
environment.variables.GLFW_IM_MODULE = "ibus";
```

The Home Manager module uses [Nix Home Utils](https://github.com/JakeHPark/nix-home-utils)' KConfig patching helper to set Plasma's Wayland input method in `~/.config/kwinrc`:

```ini
[Wayland]
InputMethod=/run/current-system/sw/share/applications/fcitx5-wayland-launcher.desktop
```

Finally, you need to prevent the normal XDG autostart route from launching a [duplicate](https://discourse.nixos.org/t/prevent-installed-service-from-autostarting-fcitx5/42685) Fcitx.

```nix
systemd.user.units."app-org.fcitx.Fcitx5@autostart.service".enable = false;
```

## Module with sensible defaults

A small Nix flake/module for declarative Fcitx5 defaults:

- Fcitx5 with configurable addons, always including `fcitx5-gtk`.
- Ordered Fcitx5 entries in Group 0, with XKB layouts automatically mapped to keyboard input methods.
- `Meta+Space` / `Shift+Meta+Space` language cycling.
- Automatic `waylandFrontend` for common Wayland desktops/window managers.
- `GLFW_IM_MODULE=ibus`.
- Home Manager activation patch for Plasma's KWin Wayland input method config.
- Duplicate Fcitx XDG autostart disabled when `systemd.user.units` exists.

## NixOS

In your flake, import the module for your host:

```nix
{
  inputs.nix-i18n-with-fcitx5 = {
    url = "github:JakeHPark/nix-i18n-with-fcitx5";
    inputs.nixpkgs.follows = "nixpkgs";
    # If you also have Nix Home Utils:
    inputs.nix-home-utils.follows = "nix-home-utils";
  };

  outputs =
    { nixpkgs, nix-i18n-with-fcitx5, ... }:
    {
      nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nix-i18n-with-fcitx5.nixosModules.default
        ];
      };
    };
}
```

## Options

The defaults provide plain English and English International:

```nix
{
  i18n.defaultLocale = "en_AU.UTF-8";

  i18nWithFcitx5 = {
    enable = true;
    # This has nothing to do with Fcitx5, but I have nowhere else to put it.
    enable24HourTime = true;

    keyboardLayouts = [
      "us"
      "us-intl"
    ];

    # `fcitx5-gtk` is always included automatically.
    addons = [ ];
  };
}
```

To add Korean:

```nix
{
  i18n.defaultLocale = "en_AU.UTF-8";

  i18nWithFcitx5 = {
    enable = true;
    enable24HourTime = true;

    keyboardLayouts = [
      "us"
      "us-intl"
      "hangul"
    ];

    addons = with pkgs; [ fcitx5-hangul ];
  };
}
```

Entries matching layouts or layout-variants from `xkeyboard-config` are converted to
Fcitx keyboard input methods. For example, `us`, `us-intl`, and `fr-oss` become
`keyboard-us`, `keyboard-us-intl`, and `keyboard-fr-oss`. Other entries are used
as Fcitx input method names, so `hangul` stays `hangul`.

There are two different defaults involved:

- `DefaultIM` is the input method Fcitx starts on. It uses the first entry in
  `keyboardLayouts` after conversion, so `us` becomes `keyboard-us` and `hangul`
  stays `hangul`.
- `Default Layout` is Fcitx's underlying XKB layout field. It must be an XKB
  layout, so the module uses the first XKB layout or layout-variant in
  `keyboardLayouts`. If the list contains only non-XKB input methods, it falls
  back to `i18nWithFcitx5.defaultKeyboardLayout`, which defaults to `us`.

For example:

```nix
{
  i18nWithFcitx5.keyboardLayouts = [
    "hangul"
    "us"
    "us-intl"
  ];
}
```

produces:

```nix
"Groups/0" = {
  "Default Layout" = "us";
  DefaultIM = "hangul";
};

"Groups/0/Items/0".Name = "hangul";
"Groups/0/Items/1".Name = "keyboard-us";
"Groups/0/Items/2".Name = "keyboard-us-intl";
```

To override one setting without losing the convenient defaults:

```nix
{
  i18nWithFcitx5.settings.globalOptions.Behavior.DefaultPageSize = 9;
}
```

Set `i18nWithFcitx5.wayland = true` or `false` to override automatic Wayland detection.

## Home Manager (for KDE)

Import the Home Manager module:

```nix
sharedModules = [
  nix-i18n-with-fcitx5.homeManagerModules.default
];
```

And then:

```nix
i18nWithFcitx5.enable = true;
```

The Home Manager module patches `.config/kwinrc` directly through a Home Manager
activation script when Home Manager can see
`services.desktopManager.plasma6.enable = true` or
`services.xserver.desktopManager.plasma5.enable = true` from the NixOS
configuration. The NixOS module does not set Plasma's KWin config globally.
