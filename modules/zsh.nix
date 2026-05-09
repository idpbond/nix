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
        "mise"
      ];
    };

    # Anything that used to live at the bottom of the hand-written .zshrc
    # belongs here. The `mise activate` line is dropped because programs.mise
    # already wires it up declaratively.
    initContent = lib.mkAfter ''
      # Visual hint that you're inside this managed environment.
      PROMPT="%F{cyan}[%m]%f $PROMPT"

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
