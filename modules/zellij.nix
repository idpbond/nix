{ pkgs, lib, ... }:

# Opt-in zellij — imported only with WITH_FISH=1 (the modern-stack trial),
# ALONGSIDE tmux, which stays the default and is left untouched. Defaults-only,
# no plugins: native session resurrection, system-clipboard copy, bundled
# themes, floating panes, mouse, truecolor.
#
# We write config.kdl as RAW KDL (via xdg.configFile) rather than
# programs.zellij.settings, because Home Manager's nix->KDL converter can't
# reliably express keybinds (repeated `bind` nodes with positional args). Raw
# KDL gives exact control and still merges with zellij's compiled-in defaults.
{
  home.packages = [ pkgs.zellij ];

  xdg.configFile."zellij/config.kdl".text = ''
    theme "tokyo-night-light"
    pane_frames false
    scrollback_editor "nvim"
    default_shell "${pkgs.fish}/bin/fish"
    copy_on_select true

    // Keep pane/tab focus navigation working even in LOCKED mode (Ctrl+g).
    // Merged on top of zellij's built-in defaults, so locked mode keeps Ctrl+g
    // (unlock) and gains these focus keys. Tradeoff: an app running in a locked
    // pane won't receive Alt+hjkl / Alt+arrows either — that's the cost of
    // keeping navigation always-available.
    keybinds {
        locked {
            bind "Alt h" "Alt Left" { MoveFocusOrTab "Left"; }
            bind "Alt l" "Alt Right" { MoveFocusOrTab "Right"; }
            bind "Alt j" "Alt Down" { MoveFocus "Down"; }
            bind "Alt k" "Alt Up" { MoveFocus "Up"; }
        }
    }
  '';
}
