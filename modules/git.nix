{ ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name  = "Ilia Partuk";
      user.email = "ilia@wearebond.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # Delta is git's pager + diff prettifier. Without it, an empty `git diff`
  # invokes less which fills the screen with `~` markers (and -X keeps them
  # around after less exits). Delta exits cleanly and gives us colored,
  # syntax-aware output.
  #
  # As of HM 2026.05 these options live at the top level under
  # `programs.delta`, not nested under `programs.git`. `enableGitIntegration`
  # used to be implicit but is now required to wire delta into git.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;       # n / N jumps between diff sections
      line-numbers = true;
      side-by-side = false;  # flip to true for split view
      paging = "always";     # always open the pager, even for short diffs
    };
  };
}
