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

# ---------- step 0: keep the login shell usable -------------------------------
#
# If the account's login shell lives in the Nix store / HM profile (e.g. a
# `chsh -s ~/.nix-profile/bin/zsh`), or is the distro zsh that --purge-pkgs is
# about to remove, the steps below delete it. sshd then accepts the key but
# cannot start the shell and drops the connection: the account is locked out.
# Move the account to a shell that survives before removing anything.

login_shell() {
  if command -v getent >/dev/null 2>&1; then
    getent passwd "$USER" | cut -d: -f7
  elif [ "$(uname -s)" = Darwin ]; then
    dscl . -read "/Users/$USER" UserShell | awk '{print $2}'
  else
    awk -F: -v u="$USER" '$1 == u { print $7 }' /etc/passwd
  fi
}

# True when the shell will not exist after this script finishes.
shell_at_risk() {
  sh_path=$1
  real=$(readlink -f "$sh_path" 2>/dev/null || printf '%s' "$sh_path")
  case "$sh_path:$real" in
    "$HOME"/.nix-profile/*|/nix/*|*:/nix/*) return 0 ;;
  esac
  [ "$purge_pkgs" = 1 ] && [ "$hm_only" = 0 ] && [ "$(uname -s)" != Darwin ] \
    && [ "${sh_path##*/}" = zsh ] && return 0
  return 1
}

# First shell from /etc/shells (then fixed fallbacks) that survives.
safe_shell() {
  for c in /bin/zsh /usr/bin/zsh /bin/bash /usr/bin/bash /bin/sh; do
    [ -x "$c" ] || continue
    shell_at_risk "$c" && continue
    if [ -r /etc/shells ] && ! grep -qx "$c" /etc/shells; then continue; fi
    printf '%s\n' "$c"
    return 0
  done
  printf '/bin/sh\n'
}

current_shell=$(login_shell || true)
if [ -n "$current_shell" ] && shell_at_risk "$current_shell"; then
  new_shell=$(safe_shell)
  warn "your login shell ($current_shell) is removed by this uninstall;"
  warn "without a change, SSH logins to $USER will fail afterwards"
  if ask "Change $USER's login shell to $new_shell first?"; then
    if command -v chsh >/dev/null 2>&1; then
      sudo chsh -s "$new_shell" "$USER"
    else
      sudo usermod -s "$new_shell" "$USER"
    fi
    [ "$(login_shell)" = "$new_shell" ] \
      || { warn "login shell change did not apply; aborting before removing anything"; exit 1; }
    log "login shell is now $new_shell"
  else
    warn "aborting: change the login shell first, e.g. sudo chsh -s $new_shell $USER"
    exit 1
  fi
fi

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

# Decrypted copies of the tracked secrets (from `nix-secrets sync`). The
# encrypted source stays in the repo, so these can be regenerated.
if [ -f "$HOME/.config/zsh/secrets.sops.zsh" ] || [ -f "$HOME/.config/fish/secrets.sops.fish" ]; then
  if ask "Remove decrypted tracked secrets (~/.config/{zsh,fish}/secrets.sops.*)?"; then
    rm -f "$HOME/.config/zsh/secrets.sops.zsh" "$HOME/.config/fish/secrets.sops.fish" \
          "$HOME/.local/state/nix-dotfiles/secrets.synced"
  fi
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
