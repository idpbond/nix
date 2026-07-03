#!/usr/bin/env bash
# Deterministic tests for the layout classifier (tmux-layout-glyph.awk), which
# emits a layout NAME. Fixtures are real #{window_layout} strings captured from
# tmux (the leading checksum is ignored by the classifier, so a dummy one is
# fine). The name -> glyph mapping (tmux-layout-glyphs.json) is pure data and
# isn't tested here.
#
# Run standalone:   ./modules/tmux-layout-glyph.test.sh
# Or via the flake: nix flake check --impure
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
AWK_FILE=${AWK_FILE:-$HERE/tmux-layout-glyph.awk}

pass=0; fail=0
# t <desc> <expected-name> <layout>
t() {
  local got; got=$(printf '%s\n' "$3" | awk -f "$AWK_FILE")
  if [ "$got" = "$2" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    printf 'FAIL %s\n       expected: [%s]\n       got:      [%s]\n       layout:   %s\n' "$1" "$2" "$got" "$3"
  fi
}

t "1 pane"         "single"      'z,200x50,0,0,0'
t "2 side-by-side" "two_col"     'z,200x50,0,0{100x50,0,0,0,99x50,101,0,1}'
t "2 stacked"      "two_row"     'z,200x50,0,0[200x25,0,0,0,200x24,0,26,1]'
t "main-left"      "main_left"   'z,200x50,0,0{100x50,0,0,0,99x50,101,0[99x25,101,0,1,99x24,101,26,2]}'
t "main-right"     "main_right"  'z,200x50,0,0{100x50,0,0[100x25,0,0,0,100x24,0,26,1],99x50,101,0,2}'
t "main-top"       "main_top"    'z,200x50,0,0[200x25,0,0,0,200x24,0,26{100x24,0,26,1,99x24,101,26,2}]'
t "main-bottom"    "main_bottom" 'z,200x50,0,0[200x25,0,0{100x25,0,0,0,99x25,101,0,1},200x24,0,26,2]'
t "3 columns"      "n_col"       'z,200x50,0,0{66x50,0,0,0,66x50,67,0,1,66x50,134,0,2}'
t "3 rows"         "n_row"       'z,200x50,0,0[200x17,0,0,0,200x16,0,18,1,200x15,0,35,2]'
t "2x2 grid"       "grid"        'z,200x50,0,0[200x24,0,0{99x24,0,0,0,100x24,100,0,1},200x25,0,25{99x25,0,25,2,100x25,100,25,3}]'
t "4 columns"      "n_col"       'z,200x50,0,0{50x50,0,0,0,49x50,51,0,1,49x50,101,0,2,49x50,151,0,3}'
t "4 rows"         "n_row"       'z,200x50,0,0[200x13,0,0,0,200x12,0,14,1,200x11,0,27,2,200x11,0,39,3]'

# main-left/right generalise: the split side having 2 OR 3 panes reads the same.
t "main-left (right split 3)"  "main_left"  'z,200x50,0,0{100x50,0,0,0,99x50,101,0[99x17,101,0,1,99x16,101,18,2,99x15,101,35,3]}'
t "main-right (left split 3)"  "main_right" 'z,200x50,0,0{100x50,0,0[100x17,0,0,0,100x16,0,18,1,100x15,0,35,2],99x50,101,0,3}'

# Genuinely mixed shapes fall back to complex.
t "complex: 3 cols, middle split"   "complex" 'z,200x50,0,0{66x50,0,0,0,66x50,67,0[66x25,67,0,1,66x24,67,26,2],66x50,134,0,3}'
t "complex: cols, first is cols"    "complex" 'z,200x50,0,0{100x50,0,0{50x50,0,0,0,49x50,51,0,1},99x50,101,0,2}'

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "tmux-layout-glyph: all $pass checks passed"
  exit 0
else
  echo "tmux-layout-glyph: $fail FAILED, $pass passed"
  exit 1
fi
