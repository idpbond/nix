{ config, pkgs, lib, system, username, homeDirectory, withGui, ... }:

{
  imports = [
    ./modules/dev-tools.nix
    ./modules/git.nix
    ./modules/zsh.nix
    ./modules/tmux.nix
    ./modules/neovim.nix
    ./modules/mise.nix
    ./modules/yazi.nix
    ./modules/yubikey.nix
  ] ++ lib.optionals withGui [
    ./modules/fonts.nix
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

  # Note: we deliberately don't install or configure Nix via Home Manager.
  # The system installer (Determinate) already provides Nix and turns flakes
  # on in /etc/nix/nix.conf, so adding a user-profile copy of upstream Nix
  # only emits spurious `unknown setting 'eval-cores' / 'lazy-trees'`
  # warnings (those are Determinate extensions vanilla Nix doesn't know).
}
