#!/usr/bin/env bash
# Activity jumplist for tmux. A pane earns a spot only when its buffer changes
# while focused (text typed/echoed or output rendered) — flipping through panes
# to look around does not pollute it. back/fwd walk that history across
# windows/sessions (vim C-o / C-i style); fwd past the newest returns "home"
# (the pane you were in when you started navigating).
#
# State (global tmux options):
#   @jl_list     space-separated pane-id history, oldest -> newest, deduped
#   @jl_idx      cursor: 1..n selects @jl_list[idx]; n+1 == "home/present"
#   @jl_home     pane you were in when navigation began (fwd target past newest)
#   @jl_jumping  "1" while a programmatic jump runs, so hooks skip recording
# Per pane:
#   @jl_hash     buffer hash captured on focus-in, compared on focus-out
set -u
MAX=30

hashof() { tmux capture-pane -p -t "$1" 2>/dev/null | cksum | cut -d' ' -f1; }
gg() { tmux show -gv "$1" 2>/dev/null; }
nth() { shift "$1"; printf '%s' "${1:-}"; }   # nth <1-based-idx> <list...>

cmd=${1:-}; pane=${2:-}

case "$cmd" in
  snapshot)                                   # focus-in: baseline the pane
    [ -n "$pane" ] && tmux set -p -t "$pane" @jl_hash "$(hashof "$pane")" 2>/dev/null
    ;;

  record)                                     # focus-out: push if it changed
    [ -z "$pane" ] && exit 0
    [ "$(gg @jl_jumping)" = 1 ] && exit 0
    old=$(tmux show -pv -t "$pane" @jl_hash 2>/dev/null)
    new=$(hashof "$pane")
    [ -n "$old" ] && [ "$old" = "$new" ] && exit 0   # nothing happened -> skip
    out=""
    for p in $(gg @jl_list); do [ "$p" != "$pane" ] && out="$out $p"; done
    out="$out $pane"
    # shellcheck disable=SC2086
    set -- $out
    while [ "$#" -gt "$MAX" ]; do shift; done
    tmux set -g @jl_list "$*"
    tmux set -g @jl_idx "$(($# + 1))"          # reset to home/present
    ;;

  back|fwd)
    # prune dead panes, recompute n
    live=" $(tmux list-panes -a -F '#{pane_id}' | tr '\n' ' ') "
    kept=""
    for p in $(gg @jl_list); do case "$live" in *" $p "*) kept="$kept $p";; esac; done
    # shellcheck disable=SC2086
    set -- $kept
    n=$#
    tmux set -g @jl_list "$*"
    [ "$n" -eq 0 ] && exit 0
    idx=$(gg @jl_idx); case "$idx" in ''|*[!0-9]*) idx=$((n + 1));; esac
    [ "$idx" -gt "$((n + 1))" ] && idx=$((n + 1))
    [ "$idx" -lt 1 ] && idx=1
    cur=$(tmux display -p '#{pane_id}')

    if [ "$cmd" = back ]; then
      [ "$idx" -eq "$((n + 1))" ] && tmux set -g @jl_home "$cur"   # entering nav
      new=$((idx - 1)); [ "$new" -lt 1 ] && new=1
    else
      new=$((idx + 1)); [ "$new" -gt "$((n + 1))" ] && new=$((n + 1))
    fi
    tmux set -g @jl_idx "$new"

    if [ "$new" -le "$n" ]; then
      # shellcheck disable=SC2086
      target=$(nth "$new" $kept)
    else
      target=$(gg @jl_home)                    # fwd past newest -> home
    fi
    [ -z "$target" ] && exit 0
    [ "$target" = "$cur" ] && exit 0

    tmux set -g @jl_jumping 1
    tmux switch-client -t "$(tmux display -p -t "$target" '#{session_name}')" 2>/dev/null
    tmux select-window -t "$(tmux display -p -t "$target" '#{window_id}')" 2>/dev/null
    tmux select-pane -t "$target" 2>/dev/null
    tmux set -g @jl_jumping 0
    ;;

  peek) echo "list=[$(gg @jl_list)] idx=$(gg @jl_idx) home=$(gg @jl_home)" ;;
esac
