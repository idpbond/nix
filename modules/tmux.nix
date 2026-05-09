{ pkgs, lib, ... }:

let
  # Plugins not curated in nixpkgs are built inline via mkTmuxPlugin.
  # First build will fail with the real sha256; paste it back here.
  easy-motion = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-easy-motion";
    version = "unstable-2024-09-01";
    src = pkgs.fetchFromGitHub {
      owner = "IngoMeyer441";
      repo = "tmux-easy-motion";
      rev = "master";
      sha256 = "sha256-Nxo8fWwgX79CrhUrHhfv8+mz3aUvPAbGmQkY34PQzKo=";
    };
  };

  themepack = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-themepack";
    version = "unstable-2024-01-01";
    src = pkgs.fetchFromGitHub {
      owner = "jimeh";
      repo = "tmux-themepack";
      rev = "master";
      sha256 = "sha256-c5EGBrKcrqHWTKpCEhxYfxPeERFrbTuDfcQhsUAbic4=";
    };
  };
in
{
  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "screen-256color";
    escapeTime = 0;
    historyLimit = 20000;
    baseIndex = 1;
    keyMode = "vi";

    # Custom prefix C-w (matches the existing config).
    prefix = "C-w";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      resurrect
      continuum
      tmux-fzf
      themepack         # provides powerline/block/cyan.tmuxtheme
      easy-motion
    ];

    # Carry over the entire hand-tuned config verbatim, minus the bits that
    # programs.tmux already manages (prefix, escape time, history-limit,
    # base-index, default-shell, key-mode, plugin loader). We rewrite the
    # tmux-themepack source path because under Nix it lives in the store.
    extraConfig = ''
      bind C-w  send-prefix
      bind-key w  send-prefix

      setw -g pane-base-index 1

      set -ga terminal-overrides ",xterm-256color:Tc"
      set -as terminal-features ",xterm-256color:RGB"

      # status bar
      set -g status-bg black
      set -g status-fg green
      set -g status-left '#h:[#S]'
      set -g status-left-length 50
      set -g status-right-length 50
      set -g status-right "%H:%M %d-%h-%Y"
      setw -g window-status-current-format "|#I:#W|"
      setw -g window-status-current-style fg=red,bg=black
      set -g automatic-rename on

      set-option -g pane-active-border-style fg=colour166

      set -g bell-action any
      setw -g window-status-bell-style bg=white,fg=red

      unbind ^A
      bind ^A select-pane -t :.+

      bind p previous-window
      bind Tab last-window
      bind Escape copy-mode

      bind V split-window -h -c "#{pane_current_path}"
      bind H split-window -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind [ copy-mode

      bind Space choose-buffer

      bind = resize-pane -D 5
      bind + resize-pane -U 5
      bind < resize-pane -L 5
      bind > resize-pane -R 5

      # Solarized-light-ish status colors
      set-option -g status-style bg=black,default
      set-window-option -g window-status-style fg=brightyellow,bg=default,dim
      set-window-option -g window-status-current-style fg=green,bg=default,bright
      set -g pane-border-style fg=white
      set -g pane-active-border-style fg=brightcyan
      set-option -g message-style fg=brightred,bg=white
      set-option -g display-panes-active-colour blue
      set-option -g display-panes-colour brightred
      set-window-option -g clock-mode-colour green

      # tmux-themepack ships its themes inside its plugin dir. The Nix-managed
      # plugin dir is exposed as $TMUX_PLUGIN_MANAGER_PATH/<name>.
      run-shell "tmux source-file ${themepack}/share/tmux-plugins/tmux-themepack/powerline/block/cyan.tmuxtheme"

      # tmux-fzf override key + options
      bind-key "C-p" run-shell -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/scripts/window.sh switch"
      set-environment -g TMUX_FZF_OPTIONS "-p -w 90% -h 60% -m"

      set -g @easy-motion-prefix "F"
      set -g @resurrect-strategy-nvim 'session'
    '';
  };
}
