{ pkgs, lib, ... }:

let
  # Treesitter parsers compiled by Nix. nvim-treesitter inside AstroNvim sees
  # any `parser/<lang>.so` on &runtimepath as already-installed and skips its
  # own download/compile path. Putting them under ~/.local/share/nvim/site/
  # keeps lazy.nvim's plugin tree untouched.
  #
  # To add a language: drop its identifier into the list and `home-manager
  # switch`. Available identifiers:
  #   nix eval --impure --expr 'with import <nixpkgs> {};
  #     builtins.attrNames vimPlugins.nvim-treesitter.builtGrammars'
  parserLanguages = [
    # AstroNvim core
    "lua" "luadoc" "vim" "vimdoc" "query" "regex"
    # C/C++ are foundational — many other parsers depend on them.
    "c" "cpp"
    # Configs / docs
    "bash" "zsh" "tmux"
    "json" "json5" "yaml" "toml" "markdown" "markdown_inline" "diff"
    "gitcommit" "gitignore" "git_config"
    # Web / TS-heavy stack from custom.lua
    "javascript" "typescript" "tsx" "html" "css"
    # Other languages we routinely touch
    "python" "rust" "go" "nix" "dockerfile" "sql"
  ];

  # Each builtGrammars.<lang> is a derivation whose `parser` is a single .so
  # file (not a directory). Stage them as `parser/<lang>.so` inside one
  # combined dir so nvim-treesitter's runtime check is satisfied.
  treesitter-parsers = pkgs.runCommand "nvim-treesitter-parsers" { } (''
    mkdir -p $out/parser
  '' + lib.concatMapStringsSep "\n" (lang: ''
    ln -s ${pkgs.vimPlugins.nvim-treesitter.builtGrammars.${lang}}/parser $out/parser/${lang}.so
  '') parserLanguages);
in
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # Opt out of the legacy Ruby/Python3 providers. AstroNvim doesn't depend
    # on them and shaving them off the closure trims ~150 MB.
    withRuby = false;
    withPython3 = false;

    # Runtime PATH that AstroNvim shells out to. We deliberately do NOT install
    # any nvim plugins through Nix — AstroNvim manages its own plugin tree via
    # lazy.nvim, and mixing the two leads to duplicate-load weirdness. The
    # contract here is: Nix supplies the binary + system tools, lazy.nvim
    # supplies the plugins, and we let Mason stay disabled (it already is in
    # the user's mason.lua scaffold) because the LSPs/formatters live in
    # dev-tools.nix instead.
    extraPackages = with pkgs; [
      # Used by AstroNvim's default plugins and the user's custom.lua.
      gcc            # treesitter parsers compile with cc
      gnumake
      git
      curl
      unzip

      # AstroNvim built-in pickers/finders.
      ripgrep
      fd

      # LSP / formatter set that the user's custom.lua references (tailwind,
      # ts_ls, eslint formatting disabled but server still attached, etc.).
      # Keeping them on $PATH — instead of via Mason — means the editor never
      # has to download a binary on first launch.
      lua-language-server
      stylua
      typescript-language-server
      vscode-langservers-extracted
      tailwindcss-language-server
      prettier
    ];
  };

  # AstroNvim's user config (init.lua + lua/...) is materialized here as
  # individual file symlinks so that lazy.nvim can still write
  # ~/.config/nvim/lazy-lock.json next to them.
  xdg.configFile."nvim/init.lua".source        = ../nvim/init.lua;
  xdg.configFile."nvim/lua".source             = ../nvim/lua;
  xdg.configFile."nvim/.luarc.json".source     = ../nvim/.luarc.json;
  xdg.configFile."nvim/.neoconf.json".source   = ../nvim/.neoconf.json;
  xdg.configFile."nvim/.stylua.toml".source    = ../nvim/.stylua.toml;
  xdg.configFile."nvim/selene.toml".source     = ../nvim/selene.toml;
  xdg.configFile."nvim/neovim.yml".source      = ../nvim/neovim.yml;

  # Drop the prebuilt parser .so files where neovim's runtimepath looks for
  # them. nvim-treesitter detects them and won't redownload.
  xdg.dataFile."nvim/site/parser".source = "${treesitter-parsers}/parser";
}

