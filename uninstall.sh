#!/usr/bin/env sh
# nix-dotfiles uninstall. Symmetric to install.sh.
#
# Removes everything install.sh and home-manager put on the host: the HM
# user profile, all Nix store contents, /nix itself, the nix-daemon service
# (if any), the nixbld group/users, and the file/dir leftovers HM doesn't
# clean up on its own. Distro packages we installed (curl, zsh, git,
# gcompat, ...) are LEFT in place because they're general-purpose; pass
# --purge-pkgs if you want them apk/apt-remove'd too.
#
# Usage:
#   ./uninstall.sh           # interactive, asks at destructive steps
#   ./uninstall.sh --yes     # non-interactive (CI / scripted use)
#   ./uninstall.sh --hm-only # only undo HM; leave Nix installed
#   ./uninstall.sh --purge-pkgs   # also apk/apt-remove the install.sh prereqs
set -eu

yes_flag=0
hm_only=0
purge_pkgs=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y)       yes_flag=1 ;;
    --hm-only)      hm_only=1 ;;
    --purge-pkgs)   purge_pkgs=1 ;;
    --help|-h)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*" >&2; }
ask() {
  if [ "$yes_flag" = 1 ]; then return 0; fi
  printf '\033[1;33m?? %s [y/N] \033[0m' "$1"
  read ans
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---------- step 1: home-manager uninstall -----------------------------------

if command -v home-manager >/dev/null 2>&1; then
  if ask "Run 'home-manager uninstall' (removes the HM profile, unlinks ~/.zshrc, etc.)?"; then
    log "uninstalling home-manager profile"
    home-manager uninstall || warn "home-manager uninstall reported errors; continuing"
  fi
else
  log "home-manager not on PATH; skipping HM uninstall"
fi

# ---------- step 2: HM/Nix leftovers HM doesn't clean ------------------------

if ask "Remove HM/Nix per-user state dirs (~/.local/state/{nix,home-manager}, ~/.cache/{nix,nvim/lazy})?"; then
  log "clearing per-user state"
  rm -rf "$HOME/.local/state/nix" \
         "$HOME/.local/state/home-manager" \
         "$HOME/.cache/nix" \
         "$HOME/.cache/nvim" \
         "$HOME/.local/share/nvim/lazy" \
         "$HOME/.local/share/nvim/site"
fi

if ask "Remove backup files HM created during initial switch (*.backup, *.pre-nix)?"; then
  find "$HOME" -maxdepth 3 \( -name '*.backup' -o -name '*.pre-nix' \) -print -exec rm -rf {} + 2>/dev/null || true
fi

# Note: ~/.config/zsh/secrets.zsh deliberately NOT removed by default — it
# contains tokens the user may want to keep around. Offer separately.
if [ -f "$HOME/.config/zsh/secrets.zsh" ]; then
  if ask "Remove ~/.config/zsh/secrets.zsh (contains the API tokens template)?"; then
    rm -f "$HOME/.config/zsh/secrets.zsh"
    rmdir "$HOME/.config/zsh" 2>/dev/null || true
  fi
fi

# ---------- step 3: Nix itself ----------------------------------------------

if [ "$hm_only" = 1 ]; then
  log "--hm-only set; leaving Nix installation intact"
  exit 0
fi

if [ -x /nix/nix-installer ]; then
  if ask "Run the Determinate Nix uninstaller (removes /nix, daemon, nixbld group)?"; then
    log "removing Nix system installation"
    sudo /nix/nix-installer uninstall --no-confirm
  fi
elif [ -d /nix ]; then
  warn "/nix exists but /nix/nix-installer is missing — manual cleanup needed:"
  warn "  https://nix.dev/manual/nix/stable/installation/uninstall"
fi

# ---------- step 4 (optional): apk/apt prereqs -------------------------------

if [ "$purge_pkgs" = 1 ]; then
  os=$([ -r /etc/os-release ] && . /etc/os-release && echo "${ID:-unknown}" || echo unknown)
  case "$os" in
    alpine)
      if ask "apk del: curl sudo xz git shadow zsh gcompat file?"; then
        sudo apk del curl sudo xz git shadow zsh gcompat file || true
      fi ;;
    debian|ubuntu)
      if ask "apt-get remove: curl xz-utils git zsh ca-certificates?"; then
        sudo apt-get remove -yqq curl xz-utils git zsh ca-certificates || true
      fi ;;
    *) warn "auto-purge for $os not implemented; skip" ;;
  esac
fi

log "done. you may want to:"
log "  - rm -rf $(pwd)               (this repo)"
log "  - open a fresh shell so PATH/ZSH state resets"
