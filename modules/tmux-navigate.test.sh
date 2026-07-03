#!/usr/bin/env bash
# Deterministic regression tests for the tmux spatial-navigation decision
# engine (tmux-navigate.awk). Pure awk over fixed #{window_layout} fixtures —
# no tmux server, no timing, no flakiness.
#
# Run standalone:   ./modules/tmux-navigate.test.sh
# Or via the flake: nix flake check --impure
#
# AWK_FILE may override the path to the decision engine (the flake check sets
# it to the store copy). Defaults to the sibling file.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
AWK_FILE=${AWK_FILE:-$HERE/tmux-navigate.awk}

pass=0; fail=0

# decide <wins> <dir> <curwin> <curpane>  -> prints the engine's decision line
decide() {
  printf '%s\n' "$1" | awk -F'|' -v dir="$2" -v curwin="$3" -v curpane="$4" -f "$AWK_FILE"
}

# t <desc> <expected> <wins> <dir> <curwin> <curpane>
t() {
  local desc=$1 expected=$2 got
  got=$(decide "$3" "$4" "$5" "$6")
  if [ "$got" = "$expected" ]; then
    pass=$((pass+1))
    # printf 'ok   %s\n' "$desc"
  else
    fail=$((fail+1))
    printf 'FAIL %s\n       expected: [%s]\n       got:      [%s]\n' "$desc" "$expected" "$got"
  fi
}

# ---- Fixtures (pane-id numbers embedded so tests read like the real thing) ----
# Single window, two panes side by side: %0 (left) | %1 (right)
HSPLIT='1|0|c,200x50,0,0{100x50,0,0,0,99x50,101,0,1}'
# Single window, two panes stacked: %0 (top) / %1 (bottom)
VSPLIT='1|0|c,200x50,0,0[200x25,0,0,0,200x24,0,26,1]'
# Single window, three panes: %0 full-height left, %1 top-right, %2 bottom-right
TRIO='1|0|c,200x50,0,0{100x50,0,0,0,99x50,101,0[99x25,101,0,1,99x24,101,26,2]}'
# Three windows: win1 h-split (%0 %1), win2 h-split (%2 %3), win3 single (%4)
W3='1|0|c,200x50,0,0{100x50,0,0,0,99x50,101,0,1}
2|0|c,200x50,0,0{100x50,0,0,2,99x50,101,0,3}
3|0|c,200x50,0,0,4'
# Two windows where win2 is zoomed (window_zoomed_flag=1)
WZOOM='1|0|c,200x50,0,0{100x50,0,0,0,99x50,101,0,1}
2|1|c,200x50,0,0{100x50,0,0,2,99x50,101,0,3}'

# ---- In-window neighbor moves ----
t "hsplit: right from %0 -> %1"        "move 1" "$HSPLIT" right 1 0
t "hsplit: left from %1 -> %0"         "move 0" "$HSPLIT" left  1 1
t "vsplit: down from %0 -> %1"         "move 1" "$VSPLIT" down  1 0
t "vsplit: up from %1 -> %0"           "move 0" "$VSPLIT" up    1 1

# ---- Single-window edges never wrap (no other window) ----
t "hsplit: left from %0 (edge)"        "edge"   "$HSPLIT" left  1 0
t "hsplit: right from %1 (edge)"       "edge"   "$HSPLIT" right 1 1
t "hsplit: up from %0 (edge)"          "edge"   "$HSPLIT" up    1 0
t "vsplit: up from %0 (edge)"          "edge"   "$VSPLIT" up    1 0
t "vsplit: left from %0 (lone window)" "edge"   "$VSPLIT" left  1 0

# ---- Three-pane spatial correctness ----
t "trio: right from %0 -> %1 (nearest overlap)" "move 1" "$TRIO" right 1 0
t "trio: left from %1 -> %0"           "move 0" "$TRIO" left  1 1
t "trio: left from %2 -> %0"           "move 0" "$TRIO" left  1 2
t "trio: down from %1 -> %2"           "move 2" "$TRIO" down  1 1
t "trio: up from %2 -> %1"             "move 1" "$TRIO" up    1 2
t "trio: up from %1 (edge)"            "edge"   "$TRIO" up    1 1
t "trio: down from %2 (edge)"          "edge"   "$TRIO" down  1 2

# ---- Cross-window wrap (direction + edge-pane landing) ----
t "wrap: left from win1 %0 -> win3 rightmost (%4)"  "wrap 3 4 0" "$W3" left  1 0
t "wrap: right from win1 %1 -> win2 leftmost (%2)"  "wrap 2 2 0" "$W3" right 1 1
t "wrap: left from win2 %2 -> win1 rightmost (%1)"  "wrap 1 1 0" "$W3" left  2 2
t "wrap: right from win3 %4 -> win1 leftmost (%0)"  "wrap 1 0 0" "$W3" right 3 4
t "wrap: left from win3 %4 -> win2 rightmost (%3)"  "wrap 2 3 0" "$W3" left  3 4
t "wrap: in-window move still wins over wrap"       "move 1"     "$W3" right 1 0
t "wrap: up never wraps (edge)"                     "edge"       "$W3" up    1 0

# ---- Zoomed-target flag is propagated (so caller preserves target zoom) ----
t "zoom-flag: wrap into zoomed win2 -> flag 1"      "wrap 2 2 1" "$WZOOM" right 1 1
t "zoom-flag: wrap into unzoomed win1 -> flag 0"    "wrap 1 1 0" "$WZOOM" left  2 2

# ---- Robustness: unknown current pane degrades to edge (no crash) ----
t "robust: missing current pane -> edge"            "edge"       "$HSPLIT" left 1 9

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "tmux-navigate: all $pass checks passed"
  exit 0
else
  echo "tmux-navigate: $fail FAILED, $pass passed"
  exit 1
fi
