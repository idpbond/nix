{ config, pkgs, lib, system, username, homeDirectory, withGui, withFish, ... }:

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
    ./modules/alacritty.nix
  ] ++ lib.optionals withGui [
    ./modules/fonts.nix
  ] ++ lib.optionals withFish [
    # Opt-in modern-stack trial: WITH_FISH=1. Adds fish + starship + zellij
    # ALONGSIDE the defaults (zsh/omz + tmux), which stay untouched and remain
    # the login shell / default multiplexer. Drop the flag (or roll back the
    # generation) to remove all three — the defaults are unaffected either way.
    ./modules/fish.nix
    ./modules/zellij.nix
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

  # Home Manager only puts $HOME/bin and ~/.nix-profile/bin on PATH (via
  # hm-session-vars.sh) — it does NOT add ~/.local/bin. Add it explicitly so
  # tools that install there land on PATH on every host: Anthropic's native
  # `claude` installer (~/.local/bin/claude), pipx, cargo-binstall, etc.
  # $HOME/bin is referenced by tmux.conf's battery script; /snap/bin keeps
  # snaps reachable on Linux. hm-session-vars.sh is sourced from ~/.zshenv, so
  # this works in login, interactive, and non-interactive shells without
  # touching the read-only HM-managed ~/.zshrc.
  home.sessionPath = [ "$HOME/.local/bin" "$HOME/bin" ]
    ++ lib.optionals pkgs.stdenv.isLinux [ "/snap/bin" ];

  programs.home-manager.enable = true;

  # Note: we deliberately don't install or configure Nix via Home Manager.
  # The system installer (Determinate) already provides Nix and turns flakes
  # on in /etc/nix/nix.conf, so adding a user-profile copy of upstream Nix
  # only emits spurious `unknown setting 'eval-cores' / 'lazy-trees'`
  # warnings (those are Determinate extensions vanilla Nix doesn't know).
}
