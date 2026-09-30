{
  nix-home-utils,
}:

{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:

let
  inherit (lib)
    attrByPath
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.i18nWithFcitx5;

  enabledAtOs = path: attrByPath path false osConfig == true;

  detectedPlasma =
    enabledAtOs [
      "services"
      "desktopManager"
      "plasma6"
      "enable"
    ]
    || enabledAtOs [
      "services"
      "xserver"
      "desktopManager"
      "plasma5"
      "enable"
    ];

in
{
  options.i18nWithFcitx5 = {
    enable = mkEnableOption "declarative Fcitx5 Home Manager defaults";

    waylandLauncher = mkOption {
      type = types.str;
      default = "/run/current-system/sw/share/applications/fcitx5-wayland-launcher.desktop";
      description = "Desktop file path to set as Plasma's Wayland input method.";
    };
  };

  config = mkIf (cfg.enable && detectedPlasma) {
    home.activation.fcitx5-i18n-kwin = mkDefault (
      nix-home-utils.lib.mkPatchIniActivation {
        inherit lib pkgs;
        path = ".config/kwinrc";
        options.Wayland.InputMethod = cfg.waylandLauncher;
      }
    );
  };
}
