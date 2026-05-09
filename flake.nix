{
  description = "Cross-platform dev environment (zsh + tmux + AstroNvim + mise) via Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      # Resolve the running host's system + username at eval time so the same
      # flake works for any user on either Linux or macOS. Requires --impure.
      system   = builtins.currentSystem;
      username =
        let envUser = builtins.getEnv "USER";
        in if envUser == "" then "user" else envUser;
    in {
      homeConfigurations.default =
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
          extraSpecialArgs = { inherit system username; };
        };
    };
}
