{ pkgs, lib, ... }:

# Opt-in fish A/B environment — imported ONLY when WITH_FISH=1 (see flake.nix).
# It lives entirely alongside the zsh/oh-my-zsh setup: it writes only fish's own
# files (~/.config/fish/*) and a fish-only starship integration, so enabling it
# changes nothing about zsh. zsh stays the login shell; run `fish` to try it.
{
  programs.fish = {
    enable = true;

    # The oh-my-zsh git aliases you actually use (from your history), ported as
    # fish ABBREVIATIONS — they expand inline as you type so you see the real
    # command. Definitions match your zsh `alias` output exactly.
    shellAbbrs = {
      g    = "git";
      gst  = "git status";
      gd   = "git diff";
      glg  = "git log --stat";
      gco  = "git checkout";
      gca  = "git commit --verbose --all";
      gp   = "git push";
      gl   = "git pull";
    };

    shellAliases = {
      l  = "ls -lah";   # matches your zsh `l`
      lg = "lazygit";
    };

    functions = {
      # Cycle to the next/previous zellij session (sorted alphabetically, wrapping).
      # Bound to Alt+Shift+J / Alt+Shift+K below. Works in locked mode because
      # those keypasses reach fish before zellij sees them.
      _zellij_next_session = ''
        if not set -q ZELLIJ_SESSION_NAME; return; end
        set sessions (zellij list-sessions --short --no-formatting 2>/dev/null | sort)
        set count (count $sessions)
        test $count -le 1; and return
        set idx 0
        for i in (seq 1 $count)
          if test $sessions[$i] = $ZELLIJ_SESSION_NAME; set idx $i; break; end
        end
        test $idx -eq 0; and return
        set next (math "$idx % $count + 1")
        zellij action switch-session $sessions[$next]
      '';
      _zellij_prev_session = ''
        if not set -q ZELLIJ_SESSION_NAME; return; end
        set sessions (zellij list-sessions --short --no-formatting 2>/dev/null | sort)
        set count (count $sessions)
        test $count -le 1; and return
        set idx 0
        for i in (seq 1 $count)
          if test $sessions[$i] = $ZELLIJ_SESSION_NAME; set idx $i; break; end
        end
        test $idx -eq 0; and return
        set prev (math "($idx - 2 + $count) % $count + 1")
        zellij action switch-session $sessions[$prev]
      '';
    };

    interactiveShellInit = ''
      set -g fish_greeting   # quiet startup

      # Prefer Nix-managed tools over Homebrew duplicates, and keep ~/.local/bin
      # (claude, etc.) + cargo on PATH — the fish equivalent of the zsh PATH
      # wiring (~/.zprofile re-prepend + home.sessionPath).
      fish_add_path --global --prepend $HOME/.nix-profile/bin $HOME/.local/bin $HOME/.cargo/bin

      # Machine-local secrets (API keys, etc.), analogous to zsh's
      # ~/.config/zsh/secrets.zsh. Regenerate in fish syntax with:
      #   grep '^export ' ~/.config/zsh/secrets.zsh | grep -v PATH= \
      #     | sed -E 's/^export ([A-Za-z_]+)=(.*)/set -gx \1 \2/' \
      #     > ~/.config/fish/secrets.fish && chmod 600 ~/.config/fish/secrets.fish
      test -r $HOME/.config/fish/secrets.fish && source $HOME/.config/fish/secrets.fish

      # Zellij session cycling — Alt+Shift+J (next) / Alt+Shift+K (prev).
      # \eJ / \eK = ESC+uppercase, sent by Alacritty with option_as_alt "Both".
      bind \eJ _zellij_next_session
      bind \eK _zellij_prev_session
    '' + lib.optionalString pkgs.stdenv.isDarwin ''

      # YubiKey / gpg-agent wiring — mirrors modules/yubikey.nix, macOS only.
      # Reuses the same cached ssh-socket file so it's just as fast.
      if type -q gpgconf
        set -gx GPG_TTY (tty)
        set -l _sock $HOME/.cache/zsh/gpg-ssh-socket
        test -r $_sock && set -gx SSH_AUTH_SOCK (cat $_sock)
        type -q gpg-connect-agent && gpg-connect-agent updatestartuptty /bye >/dev/null
      end
      test -x /opt/homebrew/bin/gpg && set -gx SOPS_GPG_EXEC /opt/homebrew/bin/gpg
    '';
  };

  # Activate mise in fish too (doesn't touch zsh's activation).
  programs.mise.enableFishIntegration = true;

  # Starship prompt — fish ONLY. zsh keeps robbyrussell completely untouched.
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = false;
    enableBashIntegration = false;
    settings = {
      add_newline = false;
      # Single-line: drop $line_break so the character sits on the same line as context.
      format = "$directory$git_branch$git_status $character";
      directory.truncation_length = 3;
      git_branch.format = "[$symbol$branch]($style) ";
      git_status.format = "([$all_status$ahead_behind]($style) )";
      character = {
        success_symbol = "[❯](green)";
        error_symbol = "[❯](red)";
      };
    };
  };
}
