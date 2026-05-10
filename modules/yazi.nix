{ pkgs, lib, ... }:

{
  programs.yazi = {
    enable = true;
    # HM's auto-generated wrapper uses `mktemp -t TEMPLATE`, which is GNU
    # coreutils syntax. Alpine's BusyBox mktemp parses -t as "use TMPDIR"
    # and treats TEMPLATE as a separate (missing) argument, producing an
    # empty path and an error. We disable HM's integration and define our
    # own portable wrapper below.
    enableZshIntegration = false;
    shellWrapperName = "yy";
  };

  # Portable `yy` wrapper: uses `mktemp PATH-TEMPLATE` instead of `-t`, which
  # works identically on GNU coreutils and BusyBox.
  programs.zsh.initContent = lib.mkAfter ''
    function yy() {
      local tmp
      tmp="$(mktemp "''${TMPDIR:-/tmp}/yazi-cwd.XXXXXX")" || return
      command yazi "$@" --cwd-file="$tmp"
      local cwd
      if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
      fi
      rm -f -- "$tmp"
    }
  '';

  # Yazi's config files are large and largely hand-tuned (theme.toml is ~770
  # lines of icon definitions). It's much cleaner to drop the .toml/.lua files
  # in directly than to translate them into Nix attribute sets. The directory
  # itself stays writable so `ya pkg` can update plugins/flavors at runtime if
  # the user wants to bypass Nix.
  xdg.configFile = {
    "yazi/yazi.toml".source    = ../yazi/yazi.toml;
    "yazi/keymap.toml".source  = ../yazi/keymap.toml;
    "yazi/theme.toml".source   = ../yazi/theme.toml;
    "yazi/init.lua".source     = ../yazi/init.lua;
    "yazi/package.toml".source = ../yazi/package.toml;

    # Plugins and flavors are vendored as full directory symlinks so yazi
    # picks them up under ~/.config/yazi/plugins/<name> and ~/.config/yazi/
    # flavors/<name> without ever calling `ya pkg add`.
    "yazi/plugins/fg.yazi".source       = ../yazi/plugins/fg.yazi;
    "yazi/plugins/git.yazi".source      = ../yazi/plugins/git.yazi;
    "yazi/plugins/lazygit.yazi".source  = ../yazi/plugins/lazygit.yazi;

    "yazi/flavors/gruvbox-material.yazi".source = ../yazi/flavors/gruvbox-material.yazi;
    "yazi/flavors/flexoki-dark.yazi".source     = ../yazi/flavors/flexoki-dark.yazi;
  };

  # Tools the user's keymap.toml + plugins shell out to: fg/lazygit are already
  # in dev-tools.nix; `file` is needed by smart_open's MIME check (Alpine's
  # busybox provides it but we make it explicit for completeness on minimal
  # systems). xdg-utils gives us xdg-open on Linux.
  home.packages = with pkgs; [
    file
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    xdg-utils  # provides xdg-open for the Linux opener variant
  ];
}
