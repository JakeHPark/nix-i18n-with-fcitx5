{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  inherit (lib)
    attrByPath
    concatMap
    elem
    findFirst
    foldl'
    hasAttrByPath
    hasPrefix
    imap0
    literalExpression
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    recursiveUpdate
    splitString
    types
    unique
    ;

  cfg = config.i18nWithFcitx5;

  hasOption = path: hasAttrByPath path options;
  enabledAt = path: attrByPath path false config == true;

  detectedWayland =
    enabledAt [
      "programs"
      "hyprland"
      "enable"
    ]
    || enabledAt [
      "programs"
      "sway"
      "enable"
    ]
    || enabledAt [
      "services"
      "desktopManager"
      "plasma6"
      "enable"
    ]
    || enabledAt [
      "services"
      "displayManager"
      "sddm"
      "wayland"
      "enable"
    ];

  waylandFrontend = if cfg.wayland == null then detectedWayland else cfg.wayland;

  xkbRules = splitString "\n" (
    builtins.readFile "${pkgs.xkeyboard_config}/share/X11/xkb/rules/base.lst"
  );

  sectionLines =
    section:
    (foldl'
      (
        state: line:
        if line == "! ${section}" then
          {
            inSection = true;
            lines = [ ];
          }
        else if state.inSection && hasPrefix "!" line then
          state // { inSection = false; }
        else if state.inSection then
          state // { lines = state.lines ++ [ line ]; }
        else
          state
      )
      {
        inSection = false;
        lines = [ ];
      }
      xkbRules
    ).lines;

  matchOrEmpty =
    regex: line:
    let
      match = builtins.match regex line;
    in
    if match == null then [ ] else match;

  xkbLayouts = concatMap (line: matchOrEmpty "^[[:space:]]+([^[:space:]]+)[[:space:]]+.*$" line) (
    sectionLines "layout"
  );

  xkbVariants = concatMap (
    line:
    let
      match = builtins.match "^[[:space:]]+([^[:space:]]+)[[:space:]]+([^:[:space:]]+):.*$" line;
    in
    if match == null then [ ] else [ "${builtins.elemAt match 1}-${builtins.elemAt match 0}" ]
  ) (sectionLines "variant");

  xkbInputMethodNames = map (layout: "keyboard-${layout}") (unique (xkbLayouts ++ xkbVariants));
  isXkbEntry = entry: elem "keyboard-${entry}" xkbInputMethodNames;
  mkInputMethodName = entry: if isXkbEntry entry then "keyboard-${entry}" else entry;
  inputMethods = map mkInputMethodName cfg.keyboardLayouts;
  defaultEntry = builtins.head cfg.keyboardLayouts;
  defaultLayout = findFirst isXkbEntry cfg.defaultKeyboardLayout cfg.keyboardLayouts;

  groupItems = foldl' recursiveUpdate { } (
    imap0 (index: name: {
      "Groups/0/Items/${toString index}".Name = name;
    }) inputMethods
  );

  defaultInputMethodSettings = recursiveUpdate {
    GroupOrder."0" = "Default";

    "Groups/0" = {
      Name = "Default";
      "Default Layout" = defaultLayout;
      DefaultIM = mkInputMethodName defaultEntry;
    };
  } groupItems;

  defaultSettings = {
    globalOptions = {
      Hotkey = {
        EnumerateWithTriggerKeys = false;
        EnumerateSkipFirst = false;
        ModifierOnlyKeyTimeout = 250;
      };

      "Hotkey/EnumerateForwardKeys"."0" = "Super+space";
      "Hotkey/EnumerateBackwardKeys"."0" = "Shift+Super+space";

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

    inputMethod = defaultInputMethodSettings;
  };

  fcitxSettings = recursiveUpdate defaultSettings cfg.settings;

  systemConfig =
    optionalAttrs
      (hasOption [
        "i18n"
        "inputMethod"
        "fcitx5"
        "settings"
      ])
      {
        i18n = {
          extraLocaleSettings.LC_TIME = mkIf cfg.enable24HourTime (mkDefault "C.UTF-8");

          inputMethod = {
            enable = mkDefault true;
            type = mkDefault "fcitx5";

            fcitx5 = {
              waylandFrontend = mkDefault waylandFrontend;
              ignoreUserConfig = mkDefault cfg.ignoreUserConfig;
              addons = unique (cfg.addons ++ [ pkgs.fcitx5-gtk ]);
              settings = fcitxSettings;
            };
          };
        };
      };

  environmentConfig =
    optionalAttrs
      (hasOption [
        "environment"
        "variables"
      ])
      {
        environment.variables.GLFW_IM_MODULE = mkDefault "ibus";
      };

  systemdConfig =
    optionalAttrs
      (hasOption [
        "systemd"
        "user"
        "units"
      ])
      {
        systemd.user.units."app-org.fcitx.Fcitx5@autostart.service".enable = mkDefault false;
      };

in
{
  options.i18nWithFcitx5 = {
    enable = mkEnableOption "declarative Fcitx5 i18n defaults";

    enable24HourTime = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to default LC_TIME to C.UTF-8 for 24-hour time.";
    };

    wayland = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = ''
        Whether to enable the Fcitx5 Wayland frontend. When null, this module
        enables it automatically for common Wayland desktop/window-manager options.
      '';
    };

    ignoreUserConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Whether Fcitx5 should ignore user configuration in ~/.config.";
    };

    addons = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = literalExpression "with pkgs; [ fcitx5-hangul ]";
      description = "Extra Fcitx5 addons to enable. fcitx5-gtk is always included.";
    };

    keyboardLayouts = mkOption {
      type = types.nonEmptyListOf types.str;
      default = [
        "us"
        "us-intl"
      ];
      example = [
        "us"
        "us-intl"
        "fr"
      ];
      description = ''
        Ordered Fcitx5 entries to place in Group 0. Entries matching a layout or
        layout-variant from xkeyboard-config become keyboard input methods, so
        "us" and "us-intl" become "keyboard-us" and "keyboard-us-intl". Other
        entries are treated as Fcitx input method names. The first entry is used
        as the group's default input method.
      '';
    };

    defaultKeyboardLayout = mkOption {
      type = types.str;
      default = "us";
      description = ''
        XKB layout to use as Fcitx5's Default Layout when keyboardLayouts does
        not contain any XKB layout entries. This does not affect DefaultIM.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''
        {
          globalOptions.Behavior.DefaultPageSize = 9;
          globalOptions."Hotkey/EnumerateForwardKeys"."0" = "Alt+space";
        }
      '';
      description = ''
        Recursive Fcitx5 settings overrides. Values here are merged over this
        module's defaults so individual settings can be changed without replacing
        the whole default configuration.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    systemConfig
    environmentConfig
    systemdConfig
    {
      assertions = [
        {
          assertion = cfg.keyboardLayouts != [ ];
          message = "i18nWithFcitx5.keyboardLayouts must contain at least one layout.";
        }
      ];
    }
  ]);
}
