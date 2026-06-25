{ pkgs, lib, ... }:

{
  # YubiKey / GPG-agent shell wiring, ported out of the org-managed ~/.zshrc
  # blocks (`yubikey-setup`, `yubikey-setup-sops`). Once Home Manager owns
  # ~/.zshrc it becomes a read-only Nix-store symlink, so the org script can no
  # longer append these blocks to it — we reproduce them declaratively instead.
  #
  # Conditionality is two-layered, by necessity:
  #
  #   1. Eval-time (macOS only). These paths/tools are Homebrew + macOS
  #      specific, so the whole block is emitted only when building for Darwin.
  #      On Linux nothing is added to the shell init at all.
  #
  #   2. Run-time (binary presence). gpgconf / gpg-connect-agent /
  #      /opt/homebrew/bin/gpg are NOT Nix-managed — they may or may not be
  #      installed on a given Mac, and that can change between switches. So we
  #      can't gate on them at eval time without going stale; instead each
  #      piece guards itself at startup and degrades to a no-op when its
  #      binary is missing, rather than erroring on every new shell.
  programs.zsh.initContent = lib.mkIf pkgs.stdenv.isDarwin (lib.mkAfter ''
    # --- gpg-agent as the SSH agent + pinentry TTY (needs gpgconf) ---
    if command -v gpgconf >/dev/null 2>&1; then
      # zsh exports $TTY, so avoid forking tty(1); fall back for safety.
      export GPG_TTY="''${TTY:-$(tty)}"

      # SSH_AUTH_SOCK = gpg-agent's ssh socket. `gpgconf --list-dirs` costs
      # ~15-30ms and the socket path is stable per machine, so cache it and read
      # the cache with $(<file) (no subprocess). Only export when non-empty — an
      # empty value would break ssh. Delete the cache file if you ever change
      # your GnuPG socketdir.
      _gpg_sock="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/gpg-ssh-socket"
      if [ -r "$_gpg_sock" ]; then
        SSH_AUTH_SOCK="$(<"$_gpg_sock")"
      else
        SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)"
        if [ -n "$SSH_AUTH_SOCK" ]; then
          mkdir -p "''${_gpg_sock:h}" 2>/dev/null
          print -r -- "$SSH_AUTH_SOCK" > "$_gpg_sock"
        fi
      fi
      [ -n "$SSH_AUTH_SOCK" ] && export SSH_AUTH_SOCK
      unset _gpg_sock

      # Point the agent at this pane's TTY for pinentry. We deliberately do NOT
      # call `gpgconf --launch gpg-agent`: even as a no-op it costs ~0.38s per
      # shell (full gpgconf config parse), which made every tmux split slow.
      # gpg-connect-agent autostarts the agent by default, so the first shell of
      # a session still brings it up — at ~0.01s, and every later pane too.
      command -v gpg-connect-agent >/dev/null 2>&1 \
        && gpg-connect-agent updatestartuptty /bye >/dev/null
    fi

    # --- pin sops at Homebrew's gpg so smartcard decryption routes through the
    #     expected gpg-agent/scdaemon (avoids a different gpg stack — e.g.
    #     MacGPG2 — picking up a different scdaemon). Only if it exists. ---
    [ -x /opt/homebrew/bin/gpg ] && export SOPS_GPG_EXEC="/opt/homebrew/bin/gpg"
  '');
}
