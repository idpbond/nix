# Classify a tmux #{window_layout} string into a layout NAME describing the
# window's pane arrangement. The name -> glyph mapping lives separately in
# tmux-layout-glyphs.json (so glyphs can be swapped without touching this
# logic). Single source of truth, shared with tmux-layout-glyph.test.sh —
# keep it pure (stdin in, name out).
#
# Input : one #{window_layout} string per line, e.g.
#           cf3a,200x50,0,0{100x50,0,0,0,99x50,101,0,1}
# Output: one name per line, one of:
#           single two_col two_row main_left main_right main_top main_bottom
#           grid n_col n_row complex
#
# tmux layout grammar: a node is  WxH,X,Y  followed by either ,id (a leaf pane)
# or a child group. '{...}' groups children left-to-right (columns); '[...]'
# groups them top-to-bottom (rows). We only need the TOP-level split type and
# the type of each top-level child (leaf / '{' / '[') to classify the shape.

# Walk the top-level children. Sets globals TOPTYPE ("{"|"["|"") and the child
# type string CT (concatenation of "L", "{", "[" per child). Returns child count.
function walk(layout,   s, i, n, c, depth) {
  CT=""; TOPTYPE=""
  s = substr(layout, index(layout, ",")+1)      # drop leading checksum
  n = length(s)
  # find the root's child bracket (first { or [); none => single pane
  for (i=1;i<=n;i++) { c=substr(s,i,1); if (c=="{"||c=="[") break }
  if (i>n) return 0
  TOPTYPE = substr(s,i,1)
  i++                                            # step inside the top bracket
  while (i<=n) {
    c = substr(s,i,1)
    if (c=="}" || c=="]") break                  # end of top container
    if (c==",") { i++; continue }                # sibling separator
    # consume this child's WxH,X,Y header (four runs of digits)
    while (i<=n && substr(s,i,1) ~ /[0-9]/) i++  # W
    i++                                          # x
    while (i<=n && substr(s,i,1) ~ /[0-9]/) i++  # H
    i++                                          # ,
    while (i<=n && substr(s,i,1) ~ /[0-9]/) i++  # X
    i++                                          # ,
    while (i<=n && substr(s,i,1) ~ /[0-9]/) i++  # Y
    c = substr(s,i,1)
    if (c=="{" || c=="[") {                       # child is a container
      CT = CT c
      depth=0
      while (i<=n) {
        c=substr(s,i,1)
        if (c=="{"||c=="[") depth++
        else if (c=="}"||c=="]") { depth--; if (depth==0){i++; break} }
        i++
      }
    } else if (c==",") {                          # child is a leaf: ,id
      CT = CT "L"
      i++                                         # ,
      while (i<=n && substr(s,i,1) ~ /[0-9]/) i++ # id
    }
  }
  return length(CT)
}

function classify(layout,   nch, i) {
  nch = walk(layout)
  if (nch==0) return "single"                     # one pane
  if (TOPTYPE=="{") {                             # columns (left-to-right)
    if (nch==2) {
      if (CT=="LL") return "two_col"              # 2 side-by-side
      if (CT=="L[") return "main_left"            # big-left + right split
      if (CT=="[L") return "main_right"           # big-right + left split
      if (CT=="[[") return "grid"                 # cols of rows
      return "complex"
    }
    for (i=1;i<=nch;i++) if (substr(CT,i,1)!="L") return "complex"
    return "n_col"                                # N columns
  }
  if (TOPTYPE=="[") {                             # rows (top-to-bottom)
    if (nch==2) {
      if (CT=="LL") return "two_row"              # 2 stacked
      if (CT=="L{") return "main_top"             # big-top + bottom split
      if (CT=="{L") return "main_bottom"          # big-bottom + top split
      if (CT=="{{") return "grid"                 # rows of cols
      return "complex"
    }
    for (i=1;i<=nch;i++) if (substr(CT,i,1)!="L") return "complex"
    return "n_row"                                # N rows
  }
  return "complex"
}

{ print classify($0) }
