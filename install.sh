#!/usr/bin/env sh
# nix-dotfiles bootstrap.
#
# Two modes:
#
#   ./install.sh
#       Personal machine: install prerequisites + Nix, drop a secrets-file
#       template, run home-manager switch, and install the self-updating
#       Claude Code + Codex CLIs for the CURRENT user.
#
#   ./install.sh --user ilia [--ssh-key 'ssh-ed25519 AAA...'] [--copy-ssh-keys]
#       Shared machine (EC2, company server): create a dedicated user with
#       sudo access and a 0700 home, install Nix system-wide (multi-user
#       daemon — other users on the box are unaffected and can run their own
#       home-manager), copy this repo into that user's home, and re-run the
#       personal-machine path as them. The invoking/default user's home is
#       never touched. Linux + systemd only.
#
#   --no-agent-clis   skip installing Claude Code and Codex (either mode).
#
# Idempotent — safe to re-run.
set -eu

flake_dir=$(cd "$(dirname "$0")" && pwd)

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31m!!  %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Run a command as root: directly when we already are root (fresh containers
# often have no sudo installed), via sudo otherwise.
asroot() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# ---------- args -------------------------------------------------------------

shared_user=""
ssh_key=""
copy_ssh_keys=0
agent_clis=1
while [ $# -gt 0 ]; do
  case "$1" in
    --user)          shared_user=${2:?--user needs a username}; shift 2 ;;
    --ssh-key)       ssh_key=${2:?--ssh-key needs a public key string}; shift 2 ;;
    --copy-ssh-keys) copy_ssh_keys=1; shift ;;
    --no-agent-clis) agent_clis=0; shift ;;
    -h|--help)       usage 0 ;;
    *)               warn "unknown argument: $1"; usage 1 ;;
  esac
done

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

  # Skip (and skip sudo entirely) when the basics are already there — the
  # common case on re-runs and for the second engineer onboarding onto a
  # shared box.
  if command -v curl >/dev/null 2>&1 && command -v git >/dev/null 2>&1 \
     && command -v xz >/dev/null 2>&1 && command -v zsh >/dev/null 2>&1; then
    log "prerequisites already present; skipping package install"
    return
  fi

  case "$os" in
    alpine)
      log "installing Alpine prerequisites (apk)"
      # gcompat provides /lib64/ld-linux-* so glibc-linked vendor binaries
      # (claude-code, some gh builds, etc.) can run on musl. file is purely
      # for future debugging.
      asroot apk add --no-progress curl sudo xz git shadow zsh gcompat file
      ;;
    debian|ubuntu)
      log "installing Debian/Ubuntu prerequisites (apt)"
      asroot apt-get update -qq
      asroot apt-get install -yqq curl xz-utils git zsh ca-certificates
      ;;
    fedora|rhel|centos|rocky|almalinux)
      log "installing $os prerequisites (dnf)"
      asroot dnf install -y curl xz git zsh
      ;;
    arch|manjaro)
      log "installing Arch prerequisites (pacman)"
      asroot pacman -S --noconfirm --needed curl xz git zsh
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
  # A fresh login shell (e.g. a just-created shared user) may not have the
  # profile hook loaded even though Nix is installed system-wide.
  command -v nix >/dev/null 2>&1 || source_nix || true
  if command -v nix >/dev/null 2>&1; then
    log "nix already installed: $(nix --version)"
    return
  fi

  init_args=""
  if [ "$os" != "macos" ] && ! has_systemd; then
    log "no systemd detected; installing Nix with --init none"
    log "(the installer's post-install SelfTest will fail because no daemon"
    log " is running yet — that's expected; we chown /nix to your user next"
    log " and use Nix in single-user mode from there.)"
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
    asroot chown -R "$USER:$(id -gn)" /nix
  fi
}

# ---------- shared-machine user bootstrap -------------------------------------

# Create a dedicated user with sudo access and a private (0700) home, hand
# them a copy of this repo, and re-run this script as them. Their
# home-manager environment is completely their own; the multi-user Nix
# daemon and store are the only shared pieces (by design — the store is
# content-addressed and per-user profiles never collide).
bootstrap_shared_user() {
  u=$1
  command -v useradd >/dev/null 2>&1 || die "useradd not found (on Alpine, install the 'shadow' package first)"

  if id -u "$u" >/dev/null 2>&1; then
    log "user $u already exists; leaving account as-is"
  else
    grp=sudo
    getent group sudo >/dev/null 2>&1 || grp=wheel
    # zsh is guaranteed by install_prereqs, which ran before us; the HM
    # zshrc in the user's home picks it up on first login.
    shell=$(command -v zsh || echo /bin/bash)
    log "creating user $u (groups: $grp, shell: $shell)"
    asroot useradd -m -G "$grp" -s "$shell" "$u"
  fi

  # Private home: nothing readable by other engineers on the box.
  log "restricting /home/$u to 0700"
  asroot chmod 700 "/home/$u"

  # Passwordless sudo: the account has no password (we never set one — SSH
  # keys or `sudo -iu` are the way in), so password-prompting sudo would
  # lock it out of privileged operations entirely.
  sudoers_file="/etc/sudoers.d/90-${u}"
  if ! asroot test -f "$sudoers_file"; then
    log "granting $u passwordless sudo ($sudoers_file)"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$u" | asroot tee "$sudoers_file" >/dev/null
    asroot chmod 0440 "$sudoers_file"
    asroot visudo -cf "$sudoers_file" >/dev/null || {
      asroot rm -f "$sudoers_file"
      die "generated sudoers entry failed visudo validation; removed it"
    }
  fi

  # SSH access is explicit, never implicit: --ssh-key installs the given
  # public key; --copy-ssh-keys copies the invoking user's authorized_keys
  # (convenient, but be aware that grants the same keys access to both
  # accounts). With neither, log in via: sudo -iu $u
  keys=""
  if [ -n "$ssh_key" ]; then
    keys=$ssh_key
  elif [ "$copy_ssh_keys" = 1 ] && [ -f "$HOME/.ssh/authorized_keys" ]; then
    warn "copying $USER's authorized_keys to $u — the same keys now open both accounts"
    keys=$(cat "$HOME/.ssh/authorized_keys")
  fi
  if [ -n "$keys" ]; then
    log "installing SSH authorized_keys for $u"
    asroot install -d -m 700 -o "$u" -g "$(id -gn "$u")" "/home/$u/.ssh"
    printf '%s\n' "$keys" | asroot tee -a "/home/$u/.ssh/authorized_keys" >/dev/null
    asroot chown "$u:$(id -gn "$u")" "/home/$u/.ssh/authorized_keys"
    asroot chmod 600 "/home/$u/.ssh/authorized_keys"
  else
    log "no SSH key requested; log in with: sudo -iu $u"
  fi

  # Hand the user their own copy of the repo (a clone under another user's
  # 0700 home would be unreadable, and git refuses repos owned by other
  # uids). Re-runs leave an existing copy alone — it may have local edits.
  repo_dst="/home/$u/nix-dotfiles"
  if asroot test -d "$repo_dst"; then
    log "$repo_dst already exists; leaving it as-is"
  else
    log "copying repo to $repo_dst"
    asroot cp -a "$flake_dir" "$repo_dst"
    asroot chown -R "$u:$(id -gn "$u")" "$repo_dst"
  fi

  log "re-running install as $u"
  flags=""
  [ "$agent_clis" = 0 ] && flags=" --no-agent-clis"
  # A login shell gives a clean environment so $USER/$HOME (which the flake
  # resolves via --impure) point at $u, not at the invoking user.
  # NIX_DOTFILES_SHARED makes the child print closing instructions addressed
  # to the person reading this terminal (the INVOKING user), not to $u.
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -iu "$u" sh -c 'cd "$HOME/nix-dotfiles" && NIX_DOTFILES_SHARED=1 ./install.sh'"$flags"
  else
    exec su - "$u" -c 'cd "$HOME/nix-dotfiles" && NIX_DOTFILES_SHARED=1 ./install.sh'"$flags"
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
# Secrets shared across machines belong in the repo's sops-encrypted
# secrets/env.yaml instead: `nix-secrets set NAME`, then commit.
# Add machine-local private exports here, e.g.:
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

# Record where this checkout lives so `nix-secrets edit/set/unset` can find
# it from any directory (the flake itself only sees its Nix store copy).
record_repo_dir() {
  mkdir -p "$HOME/.config/nix-dotfiles"
  printf '%s\n' "$flake_dir" > "$HOME/.config/nix-dotfiles/repo-dir"
}

# Offer to decrypt the tracked secrets (secrets/env.yaml) into the shell env.
# Needs a YubiKey (or a forwarded gpg-agent), so ask instead of failing.
sync_secrets() {
  ns="$HOME/.nix-profile/bin/nix-secrets"
  [ -x "$ns" ] || return 0
  if [ ! -t 0 ]; then
    warn "not a terminal; decrypt secrets later with: nix-secrets sync"
    return 0
  fi
  printf '\033[1;36m==> decrypt tracked secrets now? A YubiKey is needed. [y/N] \033[0m'
  read -r answer || answer=""
  case "$answer" in
    [yY]*) "$ns" sync || warn "secret sync failed; retry with: nix-secrets sync" ;;
    *)     log "skipped; run 'nix-secrets sync' (or 'nix-secrets skip') later" ;;
  esac
}

# Claude Code and Codex use their own native installers, not Nix: both
# update themselves in place (~/.local/share/claude, ~/.codex), which a
# read-only Nix store path cannot do. Install only when missing so re-runs
# never touch a self-updated copy. Do not also add them to dev-tools.nix;
# ~/.local/bin comes first on PATH and would shadow the Nix copy.
install_agent_clis() {
  if [ "$agent_clis" = 0 ]; then
    log "--no-agent-clis set; skipping Claude Code and Codex"
    return
  fi
  # Both installers add a PATH line to ~/.zprofile / ~/.zshrc when
  # ~/.local/bin is not on PATH yet. Those files are read-only Home Manager
  # links, and home.sessionPath already covers ~/.local/bin for new shells.
  PATH="$HOME/.local/bin:$PATH"
  export PATH

  if [ -x "$HOME/.local/bin/claude" ]; then
    log "Claude Code already installed; leaving it to self-update"
  elif ldd --version 2>&1 | grep -qi musl; then
    # The native build needs bash, libgcc, libstdc++ and a system ripgrep
    # on musl; see README "Installing Claude Code on Alpine".
    warn "musl host: install Claude Code by hand (README: Installing Claude Code on Alpine)"
  elif command -v bash >/dev/null 2>&1; then
    log "installing Claude Code (native installer)"
    curl -fsSL https://claude.ai/install.sh | bash \
      || warn "Claude Code install failed; retry: curl -fsSL https://claude.ai/install.sh | bash"
  else
    warn "bash not found; skipping Claude Code (its installer needs bash)"
  fi

  if [ -x "$HOME/.local/bin/codex" ]; then
    log "Codex already installed; leaving it to self-update"
  else
    log "installing Codex (native installer)"
    curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh \
      || warn "Codex install failed; retry: curl -fsSL https://chatgpt.com/codex/install.sh | sh"
  fi
}

# Run nvim once headlessly so lazy.nvim downloads + compiles every plugin
# before the user's first interactive launch. AstroNvim's lua tree is already
# in place; this populates ~/.local/share/nvim/lazy/ at install time instead
# of at first-open time.
#
# We pin to the committed nvim/lazy-lock.json via `Lazy! restore` rather than
# chasing latest with `Lazy! sync`. `sync` would silently drag the whole plugin
# tree forward on every bootstrap, which is how a major AstroNvim bump (and an
# incompatible mason-lspconfig) slipped in unvetted. `restore` reproduces the
# exact, tested versions on every host. To intentionally move forward, run
# `:Lazy update` interactively and re-commit nvim/lazy-lock.json.
warm_neovim() {
  if ! command -v nvim >/dev/null 2>&1; then
    warn "nvim not on PATH yet; open a new shell and run: nvim --headless '+Lazy! restore' +qa"
    return
  fi

  # Seed the pinned lockfile into the (writable) config dir if it isn't there
  # yet. We don't symlink it from Nix because lazy.nvim needs to write to it;
  # we don't clobber an existing one so a host's own `:Lazy update` survives.
  lock_src="${flake_dir}/nvim/lazy-lock.json"
  lock_dst="$HOME/.config/nvim/lazy-lock.json"
  if [ -f "$lock_src" ] && [ ! -f "$lock_dst" ]; then
    log "seeding pinned lazy-lock.json"
    mkdir -p "$(dirname "$lock_dst")"
    cp "$lock_src" "$lock_dst"
  fi

  log "warming nvim plugin cache (headless Lazy restore; takes ~30-60s)"
  nvim --headless '+Lazy! restore' '+qa' >/dev/null 2>&1 || \
    warn "headless Lazy restore exited non-zero; run :Lazy restore inside nvim"
}

# ---------- main -------------------------------------------------------------

os=$(detect_os)
log "host: $os ($(uname -m), $(uname -s))"

# Shared-machine guards fire before any installation work happens.
if [ -n "$shared_user" ]; then
  [ "$os" = "macos" ] && die "--user bootstrap is Linux-only (macOS has no useradd; create the account in System Settings)"
  has_systemd || die "--user bootstrap needs a systemd host: without it Nix runs single-user with /nix chowned to ONE user, which cannot serve a shared machine"
fi

install_prereqs "$os"
install_nix "$os"

# Shared mode: hand off to the dedicated user (never returns). The invoking
# user's home is never touched — no secrets template, no home-manager, no
# nvim cache land here.
if [ -n "$shared_user" ]; then
  bootstrap_shared_user "$shared_user"
fi

# Persistent marker that this account lives on a shared machine (set by the
# --user re-exec). The zsh prompt reads it to show [user@host] instead of
# the personal-machine [ilia].
if [ "${NIX_DOTFILES_SHARED:-0}" = 1 ] && [ ! -f "$HOME/.config/nix-dotfiles/shared-machine" ]; then
  log "marking this account as a shared-machine install"
  mkdir -p "$HOME/.config/nix-dotfiles"
  touch "$HOME/.config/nix-dotfiles/shared-machine"
fi

fix_nix_perms "$os"
create_secrets_template
record_repo_dir
run_hm_switch
install_agent_clis
warm_neovim
sync_secrets

printf '\n\033[1;32mDone.\033[0m\n\n'
if [ "${NIX_DOTFILES_SHARED:-0}" = 1 ]; then
  # This run happened as the dedicated user, but the person reading this is
  # the invoking/default user — address them, with names expanded concretely
  # so nothing accidentally applies to their own account.
  cat <<EOF
Everything above ran as ${USER}; your current shell is still your own user.

Next steps:

  1. Log in as ${USER}:
       sudo -iu ${USER}        # or: ssh ${USER}@<this-host> if you installed an SSH key

  2. If zsh isn't ${USER}'s login shell yet (freshly created accounts get it
     automatically; pre-existing ones are left alone):
       sudo chsh -s "\$(command -v zsh)" ${USER}

  3. As ${USER}, run "nix-secrets sync" if you skipped it above. Put
     machine-local tokens in ${HOME}/.config/zsh/secrets.zsh.

To re-apply changes later (as ${USER}):

  home-manager switch --impure --flake "${flake_dir}#default"
EOF
else
  cat <<EOF
Next steps:

  1. Open a new shell to pick up the new PATH:
       exec zsh

  2. If zsh isn't your login shell yet:
       sudo chsh -s "\$(command -v zsh)" "\$USER"

  3. Run "nix-secrets sync" if you skipped it above. Put machine-local
     tokens in ~/.config/zsh/secrets.zsh.

To re-apply changes later:

  home-manager switch --impure --flake "${flake_dir}#default"
EOF
fi
