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
    "javascript" "typescript" "tsx" "html" "css" "scss" "jsdoc"
    # Other languages we routinely touch
    "python" "rust" "nix" "dockerfile" "sql"
    "go" "gomod" "gosum" "gowork" "gotmpl"
    "ruby"
    "elixir" "heex" "eex" "erlang"
    "swift"
    "xml" "dtd"
    # Infra-as-code: terraform/opentofu (hcl), helm/k8s manifests ride on yaml
    "hcl" "terraform" "helm"
    "prisma"
  ];

  # Each builtGrammars.<lang> is a derivation whose `parser` is a single .so
  # file (not a directory). Stage them as `parser/<lang>.so` inside one
  # combined dir so nvim-treesitter's runtime check is satisfied.
  treesitter-parsers = pkgs.runCommand "nvim-treesitter-parsers" { } (''
    mkdir -p $out/parser
  '' + lib.concatMapStringsSep "\n" (lang: ''
    ln -s ${pkgs.vimPlugins.nvim-treesitter.builtGrammars.${lang}}/parser $out/parser/${lang}.so
  '') parserLanguages);

  # Curated highlight/indent/fold/injection queries for those same parsers.
  # nvim-treesitter's `main` branch (which AstroNvim v6 tracks) ships queries
  # under runtime/queries/ and only copies them next to a parser when you run
  # `:TSInstall`. Because we supply parsers out-of-band from the Nix store and
  # never `:TSInstall`, the queries never reach the runtimepath and treesitter
  # highlighting silently no-ops — parsers load, but
  # `vim.treesitter.query.get(lang, "highlights")` returns nil. Stage them from
  # the *same* nixpkgs nvim-treesitter the grammars come from, so grammar and
  # query versions always match, under site/queries/ (on the default rtp) as
  # `queries/<lang>/*.scm`.
  treesitter-queries = pkgs.runCommand "nvim-treesitter-queries" { } (''
    mkdir -p $out/queries
  '' + lib.concatMapStringsSep "\n" (lang: ''
    ln -s ${pkgs.vimPlugins.nvim-treesitter}/runtime/queries/${lang} $out/queries/${lang}
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
    # contract here is: Nix supplies the binary + system tools + LSP servers,
    # lazy.nvim supplies the plugins, and Mason stays disabled. Servers listed
    # here only *exist* on PATH — they attach because they're enabled in
    # nvim/lua/plugins/lsp-servers.lua (astrolsp `servers`). Keep the two lists
    # in sync when adding a language.
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
      typescript                     # tsserver itself — ts_ls falls back to this
                                     # (via PATH) when a project has no local
                                     # node_modules/typescript; without it the
                                     # server hard-errors on init
      vscode-langservers-extracted   # html / cssls / jsonls / eslint
      tailwindcss-language-server
      prettier

      # Language servers — official / de-facto-standard implementations only.
      gopls                          # Go (Go team)
      rust-analyzer                  # Rust (rust-lang org)
      pyright                        # Python (Microsoft)
      ruby-lsp                       # Ruby (Shopify; successor to Solargraph)
      bash-language-server           # bash/sh only — no zsh LSP exists (treesitter covers zsh)
      elixir-ls                      # Elixir (mature standard; official "Expert" LSP still 0.1.x)
      erlang-language-platform       # Erlang `elp` (Meta/WhatsApp; supersedes unmaintained erlang_ls)
      yaml-language-server           # YAML incl. Kubernetes/CloudFormation schemas (Red Hat)
      taplo                          # TOML
      marksman                       # Markdown
      lemminx                        # XML (Eclipse)
      docker-language-server         # Dockerfile + Compose + Bake (Docker Inc., supersedes dockerls)
      tofu-ls                        # OpenTofu/Terraform HCL (OpenTofu core team)
      postgres-language-server       # SQL/Postgres (Supabase)
      prisma-language-server         # Prisma schema (official)
      # Swift: sourcekit-lsp is NOT installed via Nix on purpose — Apple ships
      # it with the Xcode toolchain (/usr/bin/sourcekit-lsp) and the toolchain
      # copy matches the installed SDK. lsp-servers.lua enables it only when
      # the binary is present.
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

  # And the matching queries (see treesitter-queries above) so highlighting,
  # indentation and folds actually activate under AstroNvim v6's main-branch
  # nvim-treesitter.
  xdg.dataFile."nvim/site/queries".source = "${treesitter-queries}/queries";
}

