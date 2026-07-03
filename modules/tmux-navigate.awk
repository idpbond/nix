# Spatial navigation decision engine for tmux (see tmux.nix / tmuxNavigate).
#
# This file is the single source of truth for the geometry logic: it is both
# `-f`-loaded by the deployed navigation script AND exercised directly by
# tmux-navigate.test.sh. Keep it pure (no tmux calls) so it stays testable.
#
# Input (stdin), one line per window, fields separated by '|':
#   window_index | window_zoomed_flag | window_layout
# where window_layout is tmux's #{window_layout} string.
#
# Variables (-v):
#   dir     = left|right|up|down
#   curwin  = current window index
#   curpane = current pane id number (the N in %N)
#
# Output (one line):
#   move <paneid>                 in-window spatial neighbor exists
#   wrap <win> <paneid> <zoomed>  left/right edge -> prev/next window's edge pane
#   edge                          nothing in that direction (up/down edge, or lone window)

# Parse a #{window_layout} string into parallel arrays of pane geometry.
# Each leaf pane is encoded as WxH,X,Y,paneid; container nodes are WxH,X,Y
# followed by '{' or '[' (no trailing ,id), so the 5-number regex skips them.
function parse(layout, ids, X, Y, W, H,   s, tok, a, n) {
  n=0; s=layout
  while (match(s, /[0-9]+x[0-9]+,[0-9]+,[0-9]+,[0-9]+/)) {
    tok=substr(s, RSTART, RLENGTH); s=substr(s, RSTART+RLENGTH)
    split(tok, a, /[x,]/); n++
    W[n]=a[1]+0; H[n]=a[2]+0; X[n]=a[3]+0; Y[n]=a[4]+0; ids[n]=a[5]+0
  }
  return n
}
{ wl[$1]=$3; wz[$1]=$2; order[++nwin]=$1 }
END {
  ncur = parse(wl[curwin], id, X, Y, W, H)
  ci=0
  for (i=1;i<=ncur;i++) if (id[i]==curpane) ci=i
  if (!ci) { print "edge"; exit }
  cx=X[ci]; cy=Y[ci]; cw=W[ci]; ch=H[ci]

  # Nearest in-window neighbor: cross-axis ranges must overlap; pick the
  # closest along the travel axis.
  best=0; bestv=-999999
  for (i=1;i<=ncur;i++) {
    if (i==ci) continue
    if (dir=="left" || dir=="right") {
      if (Y[i]+H[i] <= cy || Y[i] >= cy+ch) continue
      if (dir=="left"  && X[i]+W[i] <= cx) { v=X[i]+W[i]; if (v>bestv){bestv=v;best=i} }
      if (dir=="right" && X[i] >= cx+cw)   { v=-X[i];     if (v>bestv){bestv=v;best=i} }
    } else {
      if (X[i]+W[i] <= cx || X[i] >= cx+cw) continue
      if (dir=="up"    && Y[i]+H[i] <= cy) { v=Y[i]+H[i]; if (v>bestv){bestv=v;best=i} }
      if (dir=="down"  && Y[i] >= cy+ch)   { v=-Y[i];     if (v>bestv){bestv=v;best=i} }
    }
  }
  if (best) { print "move", id[best]; exit }
  if (dir=="up" || dir=="down") { print "edge"; exit }

  # Left/right edge: wrap to the prev/next window by sorted index.
  if (nwin<=1) { print "edge"; exit }
  for (i=1;i<=nwin;i++) sorted[i]=order[i]+0
  for (i=1;i<nwin;i++) for (j=i+1;j<=nwin;j++) if (sorted[i]>sorted[j]){t=sorted[i];sorted[i]=sorted[j];sorted[j]=t}
  ci2=0
  for (i=1;i<=nwin;i++) if (sorted[i]==curwin+0) ci2=i
  if (dir=="left") ti=(ci2==1 ? nwin : ci2-1); else ti=(ci2==nwin ? 1 : ci2+1)
  tw=sorted[ti]

  # Land on the target window edge pane closest to the boundary we crossed:
  # coming from the left, take its rightmost pane; from the right, leftmost.
  ntar = parse(wl[tw], tid, tX, tY, tW, tH)
  tp=-1; tv=0
  for (i=1;i<=ntar;i++) {
    if (dir=="left") { if (tp<0 || tX[i] > tv) { tv=tX[i]; tp=tid[i] } }
    else             { if (tp<0 || tX[i] < tv) { tv=tX[i]; tp=tid[i] } }
  }
  print "wrap", tw, tp, wz[tw]+0
}
