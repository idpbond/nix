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
      # Resolve the running host's system + identity at eval time so the same
      # flake works for any user on either Linux or macOS. Requires --impure.
      system  = builtins.currentSystem;
      envUser = builtins.getEnv "USER";
      envHome = builtins.getEnv "HOME";

      username = if envUser == "" then "user" else envUser;

      # Trust $HOME when set — distros sometimes diverge from /home/$USER
      # (Lima/Alpine creates /home/<user>.linux, macOS uses /Users/<user>).
      isDarwin = system == "aarch64-darwin" || system == "x86_64-darwin";
      homeDirectory =
        if envHome != "" then envHome
        else if username == "root" then "/root"
        else if isDarwin then "/Users/${username}"
        else "/home/${username}";

      # Auto-on for macOS, opt-in via WITH_GUI=1 for Linux. Toggles the
      # fonts module (and anything else GUI-only we add later). Set
      # WITH_GUI=0 to skip on macOS if you ever want a headless darwin.
      withGuiEnv = builtins.getEnv "WITH_GUI";
      withGui =
        if withGuiEnv != "" then withGuiEnv != "0" && withGuiEnv != "false"
        else isDarwin;
    in {
      homeConfigurations.default =
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
          extraSpecialArgs = { inherit system username homeDirectory withGui; };
        };
    };
}
