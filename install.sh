#!/usr/bin/env sh
# nix-dotfiles bootstrap.
#
# Detects the host, installs prerequisites + Nix, fixes /nix ownership for
# daemon-less installs, drops a secrets-file template, and runs the first
# home-manager switch. Idempotent — safe to re-run.
#
# Usage: ./install.sh
set -eu

flake_dir=$(cd "$(dirname "$0")" && pwd)

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31m!!  %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- detect host ------------------------------------------------------

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos; return ;;
  esac
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo unknown
  fi
}

has_systemd() {
  [ -d /run/systemd/system ] || [ "$(cat /proc/1/comm 2>/dev/null || true)" = "systemd" ]
}

# ---------- prerequisites ----------------------------------------------------

install_prereqs() {
  os=$1
  case "$os" in
    alpine)
      log "installing Alpine prerequisites (apk)"
      sudo apk add --no-progress curl sudo xz git shadow zsh
      ;;
    debian|ubuntu)
      log "installing Debian/Ubuntu prerequisites (apt)"
      sudo apt-get update -qq
      sudo apt-get install -yqq curl xz-utils git zsh ca-certificates
      ;;
    fedora|rhel|centos|rocky|almalinux)
      log "installing $os prerequisites (dnf)"
      sudo dnf install -y curl xz git zsh
      ;;
    arch|manjaro)
      log "installing Arch prerequisites (pacman)"
      sudo pacman -S --noconfirm --needed curl xz git zsh
      ;;
    macos)
      # Stock macOS already has curl/git/xz; nothing to install.
      ;;
    *)
      warn "unrecognised distro '$os'; skipping prereqs (install curl/git/xz manually if missing)"
      ;;
  esac
}

# ---------- nix --------------------------------------------------------------

source_nix() {
  for f in /etc/profile.d/nix.sh \
           "$HOME/.nix-profile/etc/profile.d/nix.sh" \
           /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; do
    if [ -r "$f" ]; then
      # shellcheck disable=SC1090
      . "$f"
      return 0
    fi
  done
  return 1
}

install_nix() {
  os=$1
  if command -v nix >/dev/null 2>&1; then
    log "nix already installed: $(nix --version)"
    return
  fi

  init_args=""
  if [ "$os" != "macos" ] && ! has_systemd; then
    log "no systemd detected; installing Nix with --init none"
    init_args="linux --init none"
  else
    log "installing Nix (Determinate, default planner)"
  fi

  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install $init_args --no-confirm

  source_nix || die "Nix installed but profile script not found; open a new shell and re-run."
}

# /nix is root-owned after `--init none`, which prevents non-root nix calls.
# Reclaim it so the user can drive Nix without sudo.
fix_nix_perms() {
  os=$1
  if [ "$os" = "macos" ] || has_systemd; then
    return
  fi
  if [ -d /nix ] && [ "$(stat -c %u /nix 2>/dev/null || stat -f %u /nix)" != "$(id -u)" ]; then
    log "chowning /nix to $USER (single-user mode)"
    sudo chown -R "$USER:$(id -gn)" /nix
  fi
}

# ---------- secrets template -------------------------------------------------

create_secrets_template() {
  secrets="$HOME/.config/zsh/secrets.zsh"
  if [ -f "$secrets" ]; then
    return
  fi
  log "creating secrets template at $secrets"
  mkdir -p "$(dirname "$secrets")"
  cat > "$secrets" <<'EOF'
# Sourced by the HM-managed zshrc if present. Keep this file 0600.
# Add private exports here, e.g.:
# export CLAUDE_CODE_OAUTH_TOKEN='...'
# export BOND_BOX_AGENT_PORT='19821'
# export SOPS_AGE_KEY_CMD='bond-box-agent get-key'
EOF
  chmod 600 "$secrets"
}

# ---------- home-manager switch ---------------------------------------------

run_hm_switch() {
  log "applying home-manager configuration"
  if command -v home-manager >/dev/null 2>&1; then
    home-manager switch --impure --flake "${flake_dir}#default" -b backup
  else
    nix run home-manager/master -- switch --impure --flake "${flake_dir}#default" -b backup
  fi
}

# ---------- main -------------------------------------------------------------

os=$(detect_os)
log "host: $os ($(uname -m), $(uname -s))"

install_prereqs "$os"
install_nix "$os"
fix_nix_perms "$os"
create_secrets_template
run_hm_switch

printf '\n\033[1;32mDone.\033[0m\n\n'
cat <<EOF
Next steps:

  1. Open a new shell to pick up the new PATH:
       exec zsh

  2. If zsh isn't your login shell yet:
       sudo chsh -s "\$(command -v zsh)" "\$USER"

  3. Edit ~/.config/zsh/secrets.zsh and put your tokens there.

To re-apply changes later:

  home-manager switch --impure --flake "${flake_dir}#default"
EOF
