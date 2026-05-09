{ ... }:

{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;

    # Tools previously declared in ~/.config/mise/config.toml.
    # Any project-level .mise.toml still wins over these.
    globalConfig = {
      tools = {
        node = "24.4.1";
      };
    };
  };
}
