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

  # Palette for the inlined tmux-minimal-theme (binoymanoj/tmux-minimal-theme,
  # MIT) — pinned verbatim here instead of pulled as a plugin. Upstream default
  # Catppuccin-Mocha values; change these to reskin (see color-variants in the
  # upstream repo for Tokyo Night / Dracula / Gruvbox presets).
  th = {
    bg       = "#1A1D23";
    active   = "#b4befe";
    inactive = "#6c7086";
    text     = "#cdd6f4";
    accent   = "#b4befe";
    border   = "#44475a";
  };

  # Nerd Font status icons, kept in a data file (tmux-icons.json) and decoded
  # here so the raw glyphs never have to live in this .nix source. Keys:
  # session/dir/cpu/mem/date/clock/bat. Edit the JSON to swap any icon.
  icons = builtins.fromJSON (builtins.readFile ./tmux-icons.json);

  # Horizontal ellipsis (…), used as the cwd truncation marker. Decoded from
  # JSON so the raw glyph never has to be typed into this source.
  ellipsis = builtins.fromJSON ''"…"'';

  # Pane-layout glyphs, keyed by the layout NAME emitted by tmux-layout-glyph.awk
  # (single/two_col/two_row/main_left/main_right/main_top/main_bottom/grid/n_col/
  # n_row/complex). Kept as data so the glyph set can be swapped by editing one
  # JSON file. Current set: Material Design layout icons.
  layoutGlyphs = builtins.fromJSON (builtins.readFile ./tmux-layout-glyphs.json);

  # Spatial pane/window navigation.
  # Usage: tmux-navigate <left|right|up|down> [zoom]
  #
  # The model is built from #{window_layout}, NOT list-panes: the layout string
  # is zoom-independent and encodes every pane's REAL geometry (WxH,X,Y,paneid)
  # even while a pane is zoomed. (list-panes reports a zoomed pane at full-window
  # size, which destroys spatial neighbor detection.) One list-windows call
  # yields every window's layout, so all decisions are pure geometry.
  #
  # Plain (M-hjkl): move to the spatial neighbor. Within a window this unzooms
  #   and focuses the sibling. At a left/right window edge it wraps to the prev/
  #   next window, landing on that window's rightmost/leftmost pane — UNLESS the
  #   target window is itself zoomed, in which case its zoom is preserved.
  # Zoom (M-HJKL): stay within the window, never wrap, never unzoom on an edge.
  #   Move to the neighbor and zoom it; at an edge, zoom the current pane if it
  #   isn't already (a no-op if it is).
  tmuxNavigate = pkgs.writeShellScript "tmux-navigate" ''
    DIR=$1
    MODE=''${2:-plain}

    read -r CURWIN CURPANE CURZOOM <<< "$(tmux display -p '#{window_index} #{pane_id} #{window_zoomed_flag}')"
    CURPANE=''${CURPANE#%}

    WINS=$(tmux list-windows -F '#{window_index}|#{window_zoomed_flag}|#{window_layout}')

    # The geometry logic lives in tmux-navigate.awk — a single source of truth
    # shared with tmux-navigate.test.sh. See that file for the I/O contract.
    RESULT=$(printf '%s\n' "$WINS" | awk -F'|' -v dir="$DIR" -v curwin="$CURWIN" -v curpane="$CURPANE" -f ${./tmux-navigate.awk})

    read -r ACTION A B C <<< "$RESULT"

    case "$ACTION" in
      move)
        tmux select-pane -t "%$A"
        if [ "$MODE" = zoom ]; then tmux resize-pane -Z; fi
        ;;
      wrap)
        if [ "$MODE" = zoom ]; then
          # Zoom mode never crosses windows: zoom the current pane instead.
          if [ "$CURZOOM" != 1 ]; then tmux resize-pane -Z; fi
        else
          if [ "$C" != 1 ]; then
            # Target unzoomed: switch and land on its edge pane, as ONE atomic
            # command (a separate select-pane call would unzoom the window we
            # just left).
            tmux select-window -t ":$A" \; select-pane -t "%$B"
          else
            # Target window is zoomed: switch only, leaving its zoom intact.
            tmux select-window -t ":$A"
          fi
          # Switching away from a just-zoomed pane can race-clear the source
          # window's zoom flag. If the source was zoomed, restore it so zoom
          # survives leaving and returning to a tab.
          if [ "$CURZOOM" = 1 ] && [ "$(tmux display -p -t ":$CURWIN" '#{window_zoomed_flag}')" != 1 ]; then
            tmux resize-pane -Z -t ":$CURWIN"
          fi
        fi
        ;;
      edge)
        if [ "$MODE" = zoom ] && [ "$CURZOOM" != 1 ]; then tmux resize-pane -Z; fi
        ;;
    esac
    exit 0
  '';

  # Recompute every window's pane-layout glyph into its per-window @lg option.
  # Cheap (a few awk calls); run from layout-changing hooks. The classifier in
  # tmux-layout-glyph.awk is shared with tmux-layout-glyph.test.sh. We rescan
  # all windows on any hook so a single fire keeps every window consistent.
  tmuxLayoutGlyph = pkgs.writeShellScript "tmux-layout-glyph" ''
    tmux list-windows -a -F '#{window_id}|#{window_layout}' | while IFS='|' read -r wid layout; do
      name=$(printf '%s' "$layout" | awk -f ${./tmux-layout-glyph.awk})
      case "$name" in
        single)      g="${layoutGlyphs.single}" ;;
        two_col)     g="${layoutGlyphs.two_col}" ;;
        two_row)     g="${layoutGlyphs.two_row}" ;;
        main_left)   g="${layoutGlyphs.main_left}" ;;
        main_right)  g="${layoutGlyphs.main_right}" ;;
        main_top)    g="${layoutGlyphs.main_top}" ;;
        main_bottom) g="${layoutGlyphs.main_bottom}" ;;
        grid)        g="${layoutGlyphs.grid}" ;;
        n_col)       g="${layoutGlyphs.n_col}" ;;
        n_row)       g="${layoutGlyphs.n_row}" ;;
        *)           g="${layoutGlyphs.complex}" ;;
      esac
      tmux set-option -w -t "$wid" @lg "$g"
    done
  '';

  # System-info status segments (cpu | mem | bat), cross-platform. Kept in a
  # script so the % sequences never reach tmux's strftime pass (which would
  # mangle %cpu, %d, %f) and to sidestep nested shell quoting in status-right.
  tmuxSysinfo = pkgs.writeShellScript "tmux-sysinfo" ''
    case "$1" in
      cpu)
        if [ "$(uname)" = Darwin ]; then
          # decaying-average %cpu across processes, normalised by core count
          ps -A -o %cpu= | awk -v n="$(sysctl -n hw.ncpu)" '{s+=$1} END {printf "%.0f%%", n?s/n:s}'
        else
          # two /proc/stat samples 0.2s apart -> busy% over the interval
          read -r _ a b c d _ < /proc/stat; i1=$d; t1=$((a+b+c+d))
          sleep 0.2
          read -r _ a b c d _ < /proc/stat
          awk -v i="$((d-i1))" -v t="$((a+b+c+d-t1))" 'BEGIN{printf "%.0f%%", t?(1-i/t)*100:0}'
        fi ;;
      mem)
        if [ "$(uname)" = Darwin ]; then
          memory_pressure 2>/dev/null | awk '/free percentage/ {printf "%d%%", 100-$5}'
        else
          free | awk '/^Mem/ {printf "%d%%", $3/$2*100}'
        fi ;;
      bat)
        if [ "$(uname)" = Darwin ]; then
          pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -1
        else
          cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
          [ -n "$cap" ] && printf '%s%%' "$cap" || echo 'N/A'
        fi ;;
    esac
  '';
in
{
  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "screen-256color";
    escapeTime = 0;
    historyLimit = 1000000;
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
      easy-motion
    ];

    # Carry over the entire hand-tuned config verbatim, minus the bits that
    # programs.tmux already manages (prefix, escape time, history-limit,
    # base-index, default-shell, key-mode, plugin loader). The status theme is
    # the inlined tmux-minimal-theme (see the status section below).
    extraConfig = ''
      bind C-w  send-prefix
      bind-key w  send-prefix

      setw -g pane-base-index 1

      set -ga terminal-overrides ",xterm-256color:Tc"
      set -as terminal-features ",xterm-256color:RGB"

      # ─── Inlined tmux-minimal-theme (binoymanoj/tmux-minimal-theme, MIT) ───
      # Pinned verbatim rather than pulled as a plugin. Audited: pure set-option
      # + read-only #() status commands (basename/free/date/battery); no
      # network, eval, or writes. Palette lives in `th` (let block above).
      set -g status on
      set -g status-position bottom
      set -g status-interval 3
      set -g status-justify left
      set -g status-style "bg=${th.bg},fg=${th.text}"
      set -g status-left-length 100
      set -g status-right-length 100

      set -g message-style "bg=${th.bg},fg=${th.text},bold"
      set -g message-command-style "bg=${th.bg},fg=${th.text},bold"
      set -g mode-style "bg=${th.active},fg=${th.bg}"
      set -g clock-mode-colour "${th.active}"
      set -g clock-mode-style 24

      # Window list. Styles are set explicitly (not only in the -format) so they
      # override any window-status-*-style leaking from the stray ~/.tmux.conf,
      # keeping the window-name background identical to the rest of the bar.
      set -g window-status-style "fg=${th.inactive},bg=${th.bg}"
      set -g window-status-current-style "fg=${th.active},bg=${th.bg}"
      set -g window-status-format "#[fg=${th.inactive},bg=${th.bg}] #I:#W "
      set -g window-status-current-format "#[fg=${th.active},bg=${th.bg},bold] #I:#W "
      set -g window-status-separator ""
      set -g automatic-rename on

      # status-left: session name (double space so the icon doesn't touch #S).
      set -g status-left "#[fg=${th.accent},bold] ${icons.session}  #S #[fg=${th.inactive}]│ "

      # status-right sections: cwd · pane-layout glyph · cpu · memory · battery.
      # cwd is the full pane path, kept to the last 50 chars with a leading …
      # marker on overflow (#{=/-50/…:…}). #{@lg} resolves to the CURRENT window
      # here (status is drawn in the active window's context), a live layout
      # indicator. cpu/mem/bat come from the cross-platform tmux-sysinfo helper.
      set -g status-right "#[fg=${th.accent}] ${icons.dir}  #[fg=${th.text}]#{=/-50/${ellipsis}:#{pane_current_path}} #[fg=${th.inactive}]│ #[fg=${th.accent},bold] #{@lg} #[nobold]#[fg=${th.inactive}]│ #[fg=${th.accent}]${icons.cpu}  #[fg=${th.text}]#(${tmuxSysinfo} cpu) #[fg=${th.inactive}]│ #[fg=${th.accent}]${icons.mem}  #[fg=${th.text}]#(${tmuxSysinfo} mem) #[fg=${th.inactive}]│ #[fg=${th.accent}]${icons.bat}  #[fg=${th.text}]#(${tmuxSysinfo} bat)"

      # Per-window layout glyph in @lg (the status-right section shows the
      # current window's). Recompute on every layout-changing event, and once
      # now so existing windows are populated when the config is (re)loaded.
      set-hook -g after-split-window  "run-shell ${tmuxLayoutGlyph}"
      set-hook -g after-kill-pane     "run-shell ${tmuxLayoutGlyph}"
      set-hook -g pane-exited         "run-shell ${tmuxLayoutGlyph}"
      set-hook -g after-select-layout "run-shell ${tmuxLayoutGlyph}"
      set-hook -g after-new-window    "run-shell ${tmuxLayoutGlyph}"
      set-hook -g window-linked       "run-shell ${tmuxLayoutGlyph}"
      run-shell ${tmuxLayoutGlyph}

      # Pane title bars — strip at top of each pane border showing index,
      # running command, and current directory basename.
      # Rename a pane with prefix+. (analogous to prefix+, for windows).
      set -g pane-border-status top
      set -g pane-border-format " #{pane_index}: #{?#{!=:#{pane_title},#{host}},#{pane_title},#{pane_current_command}} "
      bind M command-prompt -p "Rename pane:" "select-pane -T '%%'"

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

      # Prefix-free pane navigation — spatial model, see tmuxNavigate in the let
      # block. One list-panes snapshot drives all decisions; no per-query races.
      bind -n M-h run-shell "${tmuxNavigate} left"
      bind -n M-j run-shell "${tmuxNavigate} down"
      bind -n M-k run-shell "${tmuxNavigate} up"
      bind -n M-l run-shell "${tmuxNavigate} right"

      # Zoomed navigation: move between panes while keeping/entering zoom.
      # At a same-window edge: zoom current pane. Never crosses to another window.
      bind -n M-H run-shell "${tmuxNavigate} left zoom"
      bind -n M-J run-shell "${tmuxNavigate} down zoom"
      bind -n M-K run-shell "${tmuxNavigate} up zoom"
      bind -n M-L run-shell "${tmuxNavigate} right zoom"

      bind [ copy-mode

      bind Space choose-buffer

      bind = resize-pane -D 5
      bind + resize-pane -U 5
      bind < resize-pane -L 5
      bind > resize-pane -R 5

      # Pane display indicator colors (kept from the old config; the minimal
      # theme doesn't set these).
      set-option -g display-panes-active-colour blue
      set-option -g display-panes-colour brightred

      # tmux-fzf override key + options
      bind-key "C-p" run-shell -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/scripts/window.sh switch"
      set-environment -g TMUX_FZF_OPTIONS "-p -w 90% -h 60% -m"

      set -g @easy-motion-prefix "F"
      set -g @resurrect-strategy-nvim 'session'
    '';
  };
}
