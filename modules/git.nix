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
}
