{ pkgs, lib, ... }:

{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    # Provides `yy` wrapper that exits to the directory yazi was last in.
    # `Y` is occasionally used by other tools; keeping `yy` stops collisions.
    shellWrapperName = "yy";
  };

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
