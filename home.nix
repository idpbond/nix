{ config, pkgs, lib, system, username, homeDirectory, ... }:

{
  imports = [
    ./modules/dev-tools.nix
    ./modules/git.nix
    ./modules/zsh.nix
    ./modules/tmux.nix
    ./modules/neovim.nix
    ./modules/mise.nix
  ];

  home.username = username;
  home.homeDirectory = homeDirectory;

  # Pin to whatever release-format the flake uses; Home Manager surfaces this.
  home.stateVersion = "25.05";

  # Locale and terminal hints used across tools.
  home.sessionVariables = {
    EDITOR   = "nvim";
    VISUAL   = "nvim";
    PAGER    = "less -FRX";
    LC_ALL   = "C.UTF-8";
    LANG     = "C.UTF-8";
    COLORTERM = "24bit";
  };

  # ~/.local/bin is on PATH by default in HM, but make sure $HOME/bin (referenced
  # from tmux.conf for the battery script) and snap stay reachable on Linux.
  home.sessionPath = [ "$HOME/bin" ]
    ++ lib.optionals pkgs.stdenv.isLinux [ "/snap/bin" ];

  programs.home-manager.enable = true;

  # Manage Nix itself via HM so flakes are always on, even if the user installed
  # Nix in single-user mode without a system-level nix.conf.
  nix = {
    package = pkgs.nix;
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
