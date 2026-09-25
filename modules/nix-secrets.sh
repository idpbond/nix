# nix-secrets: manage the sops-encrypted env file (secrets/env.yaml) and
# decrypt it into shell files that zsh and fish source at startup.
#
# Wrapped by modules/secrets.nix (writeShellApplication), which provides sops,
# jq, yq and coreutils on PATH and sets:
#   NIX_SECRETS_ACTIVATED_FILE  encrypted env.yaml of the active HM generation
#   NIX_SECRETS_PUBKEYS         armored public keys of all recipients
# gpg is deliberately NOT provided: it must be the host's gpg that can reach
# the YubiKey (see modules/yubikey.nix and SOPS_GPG_EXEC).

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nix-dotfiles"
stamp="$state_dir/secrets.synced"
repo_marker="${XDG_CONFIG_HOME:-$HOME/.config}/nix-dotfiles/repo-dir"
zsh_out="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/secrets.sops.zsh"
fish_out="${XDG_CONFIG_HOME:-$HOME/.config}/fish/secrets.sops.fish"

die() { printf 'nix-secrets: %s\n' "$*" >&2; exit 1; }
say() { printf 'nix-secrets: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: nix-secrets <command> [args]

  sync [FILE]   Decrypt secrets (default: the repo checkout's copy, else the
                active Home Manager generation's) into
                ~/.config/zsh/secrets.sops.zsh and
                ~/.config/fish/secrets.sops.fish. Needs a YubiKey.
  edit          Open the repo's secrets/env.yaml in $EDITOR via sops, then sync.
  set KEY       Set KEY (value read from stdin, or a hidden prompt), then sync.
  unset KEY     Remove KEY, then sync.
  list          List secret names (no decryption).
  status        Show paths and whether decrypted files match the active copy.
  skip          Mark the active copy as handled without decrypting (for hosts
                with no YubiKey access). Silences the switch-time notice.
  updatekeys    Re-encrypt the data key for the recipients in .sops.yaml.

Edit commands need the repo checkout. It is found via $NIX_DOTFILES_DIR, the
current git repo, or ~/.config/nix-dotfiles/repo-dir (written by install.sh).
Commit and push secrets/env.yaml afterwards; other hosts get it on
`git pull` + `home-manager switch`, then `nix-secrets sync`.
EOF
}

# Locate the writable repo checkout (not the Nix store copy).
repo_dir() {
  local d=""
  if [ -n "${NIX_DOTFILES_DIR:-}" ]; then
    d=$NIX_DOTFILES_DIR
  elif d=$(git rev-parse --show-toplevel 2>/dev/null) \
    && [ -f "$d/.sops.yaml" ] && [ -f "$d/secrets/env.yaml" ]; then
    :
  elif [ -r "$repo_marker" ]; then
    d=$(<"$repo_marker")
  else
    d=""
  fi
  [ -n "$d" ] && [ -f "$d/secrets/env.yaml" ] \
    || die "cannot find the nix-dotfiles checkout; run inside it or set NIX_DOTFILES_DIR"
  # Remember it for next time (cheap; keeps the marker current if moved).
  mkdir -p "$(dirname "$repo_marker")"
  printf '%s\n' "$d" > "$repo_marker"
  printf '%s\n' "$d"
}

# Prefer the checkout (it has edits not yet switched in); fall back to the
# active generation's copy on hosts where the checkout can't be found.
default_src() {
  local d
  if d=$(repo_dir 2>/dev/null); then
    printf '%s\n' "$d/secrets/env.yaml"
  else
    printf '%s\n' "$NIX_SECRETS_ACTIVATED_FILE"
  fi
}

hash_of() { sha256sum "$1" | cut -d' ' -f1; }

# Make sure gpg knows the recipients and, when possible, the card key stubs.
# On a fresh host this is what lets a plugged-in YubiKey decrypt.
prepare_gpg() {
  command -v "${SOPS_GPG_EXEC:-gpg}" >/dev/null 2>&1 \
    || die "gpg not found; install GnuPG (macOS: Homebrew gnupg; Linux: distro gnupg + pcscd)"
  local gpg=${SOPS_GPG_EXEC:-gpg} fpr missing=0 have_secret=0
  while read -r fpr; do
    "$gpg" --list-keys "$fpr" >/dev/null 2>&1 || missing=1
    "$gpg" --list-secret-keys "$fpr" >/dev/null 2>&1 && have_secret=1
  done < <(grep -oE '[0-9A-F]{40}' "$NIX_SECRETS_ACTIVATED_FILE" | sort -u)
  if [ "$missing" = 1 ]; then
    say "importing recipient public keys"
    "$gpg" --batch --quiet --import "$NIX_SECRETS_PUBKEYS" \
      || die "gpg --import failed"
  fi
  if [ "$have_secret" = 0 ]; then
    # Creates the secret-key stubs that point at the inserted card.
    "$gpg" --card-status >/dev/null 2>&1 \
      || say "no YubiKey secret key found; insert a YubiKey (or forward gpg-agent)"
  fi
}

# Render decrypted JSON ({"KEY": "value", ...}) as shell assignments.
# @sh gives POSIX single-quoting (valid in zsh); fish single quotes only
# treat \\ and \' specially, so escape those two.
render() {
  local shell=$1
  jq -r --arg shell "$shell" --arg q "'" '
    if type != "object" then error("secrets must be a flat YAML map") else . end
    | to_entries[]
    | if (.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) | not
        then error("invalid variable name: \(.key)") else . end
    | if (.value | type) == "object" or (.value | type) == "array"
        then error("\(.key): value must be a scalar") else . end
    | (.value | tostring) as $v
    | if $shell == "zsh" then "export \(.key)=\($v | @sh)"
      else "set -gx \(.key) \($q)\($v | gsub("\\\\"; "\\\\") | gsub($q; "\\\($q)"))\($q)"
      end'
}

# Write $2 to $1 atomically with mode 0600.
write_secret_file() {
  local dst=$1 content=$2 tmp
  mkdir -p "$(dirname "$dst")"
  tmp=$(mktemp "$dst.XXXXXX")
  {
    printf '# Generated by nix-secrets from secrets/env.yaml. Do not edit;\n'
    printf '# use "nix-secrets edit" (or ~/.config/zsh/secrets.zsh for local-only values).\n'
    if [ -n "$content" ]; then printf '%s\n' "$content"; fi
  } > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$dst"
}

cmd_sync() {
  local src=${1:-} json zsh_lines fish_lines
  [ -n "$src" ] || src=$(default_src)
  [ -f "$src" ] || die "no such file: $src"
  prepare_gpg
  say "decrypting $src (touch the YubiKey if it blinks)"
  json=$(sops decrypt --output-type json "$src") || die "decryption failed"
  zsh_lines=$(render zsh <<<"$json") || die "cannot render secrets"
  fish_lines=$(render fish <<<"$json") || die "cannot render secrets"
  umask 077
  write_secret_file "$zsh_out" "$zsh_lines"
  write_secret_file "$fish_out" "$fish_lines"
  mkdir -p "$state_dir"
  hash_of "$src" > "$stamp"
  say "wrote $(jq 'length' <<<"$json") secret(s); open a new shell (or: source $zsh_out)"
}

cmd_status() {
  local src want have="(never)"
  src=$(default_src)
  want=$(hash_of "$src")
  [ -r "$stamp" ] && have=$(<"$stamp")
  printf 'source:       %s\n' "$src"
  printf 'active copy:  %s\n' "$NIX_SECRETS_ACTIVATED_FILE"
  printf 'zsh output:   %s\n' "$zsh_out"
  printf 'fish output:  %s\n' "$fish_out"
  if [ "$want" = "$have" ]; then
    echo "state:        in sync"
  else
    echo "state:        out of date; run: nix-secrets sync"
  fi
}

cmd_list() {
  yq -r 'del(.sops) | keys | .[]' "$(default_src)"
}

# Edit commands operate on the repo checkout, then sync from it so this
# host's shells see the change without waiting for `home-manager switch`.
with_repo() {
  local d
  d=$(repo_dir)
  cd "$d" || exit
  prepare_gpg
  "$@"
  cmd_sync "$d/secrets/env.yaml"
  say "remember to commit secrets/env.yaml"
}

valid_key() {
  [[ ${1:-} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "invalid variable name: ${1:-<empty>}"
}

do_set() {
  local key=$1 value
  if [ -t 0 ]; then
    read -rsp "Value for $key: " value; echo >&2
  else
    value=$(cat)
  fi
  # sops set takes a JSON-encoded value; stdin avoids exposing it in ps.
  jq -n --arg v "$value" '$v' \
    | sops set --value-stdin secrets/env.yaml "[\"$key\"]"
}

# `sops edit` exits 200 when nothing changed; that is not an error here.
do_edit() {
  local rc=0
  sops edit secrets/env.yaml || rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 200 ] || exit "$rc"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
  sync)       cmd_sync "$@" ;;
  edit)       with_repo do_edit ;;
  set)        valid_key "${1:-}"; with_repo do_set "$1" ;;
  unset)      valid_key "${1:-}"; with_repo sops unset secrets/env.yaml "[\"$1\"]" ;;
  list)       cmd_list ;;
  status)     cmd_status ;;
  skip)       mkdir -p "$state_dir"; hash_of "$NIX_SECRETS_ACTIVATED_FILE" > "$stamp" ;;
  updatekeys) d=$(repo_dir); cd "$d" || exit; prepare_gpg; sops updatekeys --yes secrets/env.yaml ;;
  -h|--help|help|"") usage ;;
  *)          usage >&2; exit 2 ;;
esac
