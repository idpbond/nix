{ pkgs, lib, ... }:

{
  # Tools that aren't tied to a specific program module above.
  # These replace what's currently a mix of apt packages, "missing" binaries,
  # and language-runtime helpers. They are in scope for every shell.
  home.packages = with pkgs; [
    # Search & navigation (referenced by AstroNvim/Snacks/fzf integrations).
    ripgrep        # rg
    fd
    bat
    eza
    fzf            # also wired up via programs.fzf in zsh.nix
    tree
    jq
    yq-go

    # Git ergonomics.
    lazygit
    gh
    delta

    # Build tooling (treesitter parsers, npm postinstalls, etc.).
    gnumake
    gcc
    pkg-config
    unzip
    curl
    wget

    # Real bash. Some scripts (e.g. tmux-fzf) start with `#!/usr/bin/env bash`
    # and use bash-specific syntax like ${BASH_SOURCE[0]}. On Alpine /bin/bash
    # is BusyBox ash, which fails on those substitutions. Nix-installed bash
    # makes ~/.nix-profile/bin/bash the first match on PATH everywhere.
    bashInteractive

    # Real GNU less. Tools like delta invoke their pager with long-form
    # options (--RAW-CONTROL-CHARS, --quit-if-one-screen, --mouse, ...)
    # which BusyBox less rejects outright. Nix's less takes precedence on
    # PATH so delta / git / man / etc. get the option set they expect.
    less

    # Languages & runtimes that AstroNvim's LSP/format tooling expects, and
    # that other tools (npm-based CLIs, claude-code, etc.) need on PATH.
    # mise can still layer additional versions on top per-project via
    # `.mise.toml`, but a sane default lives here so musl-only distros
    # like Alpine don't need to compile node from source.
    python3
    nodejs_24

    # Lua dev for AstroNvim itself.
    lua-language-server
    stylua
    selene
    tree-sitter

    # Web/JS formatters & linters used from custom.lua's tailwind/cva config.
    prettier
    typescript-language-server
    vscode-langservers-extracted   # html/css/json/eslint
    tailwindcss-language-server

    # Shell scripting safety net.
    shellcheck
    shfmt

    # Encrypted-config tools the user has env vars for.
    sops
    age
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux-only conveniences.
    xclip          # tmux-yank backend on X11
    wl-clipboard   # tmux-yank backend on Wayland
  ];

  # direnv pairs nicely with mise — per-project tool/env activation without
  # polluting the global shell.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };
}
