{
  description = "Convenient declarative Fcitx5 i18n defaults for NixOS and Plasma";

  inputs = {
    nix-home-utils = {
      url = "github:JakeHPark/nix-home-utils";
      flake = false;
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nix-home-utils,
      nixpkgs,
      ...
    }:
    let
      nixHomeUtils = {
        lib = import "${nix-home-utils}/lib" {
          inherit (nixpkgs) lib;
        };
      };

      nixosModule = import ./modules/fcitx5-i18n.nix;
      homeManagerModule = import ./modules/home.nix {
        nix-home-utils = nixHomeUtils;
      };
    in
    {
      nixosModules.default = nixosModule;
      nixosModules.fcitx5-i18n = nixosModule;

      homeManagerModules.default = homeManagerModule;
      homeManagerModules.fcitx5-i18n = homeManagerModule;
    };
}
