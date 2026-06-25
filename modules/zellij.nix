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
    theme "flexoki-dark"
    pane_frames false
    scrollback_editor "nvim"
    default_shell "${pkgs.fish}/bin/fish"
    copy_on_select true

    // Flexoki Dark (kepano's "inky" scheme), defined inline (no plugin) so it
    // works regardless of whether this zellij build bundles it — and the dark
    // background fixes the pane-highlight contrast on a black terminal.
    themes {
        flexoki-dark {
            fg "#CECDC3"
            bg "#100F0F"
            black "#100F0F"
            red "#AF3029"
            green "#879A39"
            yellow "#D0A215"
            blue "#4385BE"
            magenta "#CE5D97"
            cyan "#3AA99F"
            white "#CECDC3"
            orange "#DA702C"
        }
    }

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
