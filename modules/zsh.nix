{ pkgs, lib, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      share = true;
    };

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "gitfast"
        "dotenv"
        "docker"
        "docker-compose"
        "colored-man-pages"
        # "mise" intentionally omitted: the OMZ mise plugin just runs
        # `eval "$(mise activate zsh)"`, which programs.mise.enableZshIntegration
        # already does — including it double-activated mise (~20ms/shell wasted).
      ];

      # Source the user's tracked custom *.zsh files (e.g. git-resign) the same
      # way the old ~/.oh-my-zsh/custom/ did. HM's oh-my-zsh uses its own $ZSH
      # in the Nix store, so the old ~/.oh-my-zsh/custom/ is no longer read —
      # these live in the repo now. ZSH_CUSTOM points here; OMZ sources
      # $ZSH_CUSTOM/*.zsh at startup.
      custom = "${../zsh/custom}";
    };

    # Anything that used to live at the bottom of the hand-written .zshrc
    # belongs here. The `mise activate` line is dropped because programs.mise
    # already wires it up declaratively.
    initContent = lib.mkAfter ''
      # Visual hint that you're inside this managed environment.
      PROMPT="%F{cyan}[%m]%f $PROMPT"

      # On musl-based hosts (Alpine, Void, ...) tell mise to prefer musl-built
      # binaries when a registry provides both variants. Without this, mise
      # falls back to glibc URLs and downloads binaries that can't run on
      # Alpine. Recognised by mise ≥ 2026.4.23; ignored by older versions.
      # See https://github.com/jdx/mise CHANGELOG for "Global libc setting".
      if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        export MISE_LIBC=musl
      fi

      # Pull secrets out of version control. Create ~/.config/zsh/secrets.zsh
      # with `chmod 600` and put CLAUDE_CODE_OAUTH_TOKEN, BOND_BOX_AGENT_PORT,
      # SOPS_AGE_KEY_CMD, etc. in there.
      [[ -r "$HOME/.config/zsh/secrets.zsh" ]] && source "$HOME/.config/zsh/secrets.zsh"
    '';
  };

  # fzf integration replaces the manual `source <(fzf --zsh)` line.
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
  };
}
