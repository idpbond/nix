-- Enable language servers whose binaries Nix puts on PATH (see
-- modules/neovim.nix → extraPackages). Mason is unused in this setup, and
-- AstroLSP only auto-enables Mason-installed servers — anything provided
-- out-of-band must be listed in `servers` explicitly or it never attaches.
-- Names are nvim-lspconfig config names. Keep this list in sync with
-- extraPackages when adding a language.

---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    opts = {
      filetypes = {
        -- Neovim leaves `.tofu` undetected and only fuzzily detects `.tf`
        -- (content heuristic that can land on the ancient "tf" filetype).
        -- Pin both to `terraform`: tofu-ls attaches to it and the terraform
        -- treesitter parser highlights OpenTofu fine (same HCL).
        extension = { tofu = "terraform", tf = "terraform" },
        -- Compose files detect as plain `yaml`; the Docker language server
        -- only attaches to the dedicated compose filetype (as in VS Code).
        -- Treesitter keeps parsing it as yaml — see the register() call below.
        filename = {
          ["docker-compose.yml"] = "yaml.docker-compose",
          ["docker-compose.yaml"] = "yaml.docker-compose",
          ["compose.yml"] = "yaml.docker-compose",
          ["compose.yaml"] = "yaml.docker-compose",
        },
      },
      autocmds = {
        -- Ruby's ftplugin sets keywordprg=ri, so K in a buffer without an
        -- attached LSP shells out to ri — on machines without a Ruby
        -- toolchain that surfaces as "command not found: ri" in a dead
        -- terminal split. Fall back to :help when ri doesn't exist; when it
        -- does (machines with a real Ruby), keep genuine ri docs.
        ruby_keywordprg_fallback = {
          {
            event = "FileType",
            pattern = { "ruby", "eruby" },
            desc = "K falls back to :help when ri is not installed",
            callback = function(args)
              if vim.fn.executable "ri" == 0 then vim.bo[args.buf].keywordprg = "" end
            end,
          },
        },
      },
    },
  },
  {
    "AstroNvim/astrolsp",
    ---@param opts AstroLSPOpts
    opts = function(_, opts)
      -- Compose buffers have filetype yaml.docker-compose but no parser of
      -- that name; parse them with the yaml grammar.
      vim.treesitter.language.register("yaml", { "yaml.docker-compose" })

      local servers = {
        "lua_ls",
        -- web stack
        "ts_ls",
        "html",
        "cssls",
        "jsonls",
        "eslint",
        "tailwindcss",
        -- configs / docs
        "yamlls",
        "taplo",
        "marksman",
        "lemminx",
        -- languages
        "gopls",
        "rust_analyzer",
        "pyright",
        "ruby_lsp",
        "bashls", -- bash/sh only; zsh has no LSP (treesitter highlighting only)
        "elixirls",
        "elp",
        -- infra / data
        "docker_language_server", -- Dockerfile + docker-compose
        "tofu_ls", -- OpenTofu + Terraform (k8s/CloudFormation YAML ride on yamlls)
        -- postgres_lsp ships workspace_required=true upstream: it attaches
        -- only in projects containing postgres-language-server.jsonc (it
        -- wants a DB connection to be useful). Plain .sql files elsewhere
        -- get treesitter highlighting only.
        "postgres_lsp",
        "prismals",
      }

      -- Swift: only on machines with an Apple toolchain (macOS). The server
      -- ships with Xcode/CLT, not Nix, so gate on the binary actually existing.
      if vim.fn.executable "sourcekit-lsp" == 1 then table.insert(servers, "sourcekit") end

      opts.servers = require("astrocore").list_insert_unique(opts.servers, servers)

      -- ts_ls needs the `typescript` package itself (tsserver), resolved from
      -- the workspace's node_modules. In projects without one it refuses to
      -- initialize, so give it a fallback derived from whatever `tsserver` is
      -- on PATH — Nix's typescript from extraPackages, or a mise-managed
      -- `npm install -g typescript` if that comes first. fallbackPath is only
      -- consulted when the workspace has no typescript, so project-pinned
      -- versions still win. Both Nix and mise/npm use the standard npm prefix
      -- layout (<prefix>/bin/tsserver, <prefix>/lib/node_modules/typescript).
      local ts_fallback
      local tsserver_bin = vim.fn.exepath "tsserver"
      if tsserver_bin ~= "" then
        local lib = vim.fs.normalize(
          vim.fs.joinpath(vim.fs.dirname(tsserver_bin), "..", "lib", "node_modules", "typescript", "lib")
        )
        if vim.uv.fs_stat(vim.fs.joinpath(lib, "tsserver.js")) then ts_fallback = lib end
      end

      opts.config = require("astrocore").extend_tbl(opts.config, {
        ts_ls = { init_options = { tsserver = { fallbackPath = ts_fallback } } },

        -- Ruby: refuse to run the Nix fallback ruby-lsp against a bundler
        -- workspace (custom root_dir below). ruby-lsp serves projects by
        -- composing a bundle from the project's Gemfile, which must run
        -- under the project's own Ruby — native gems are built for it; the
        -- Nix copy pins Nix's Ruby and dies with "quit with exit code 1".
        -- Standalone files stay served by the fallback; bundler projects get
        -- a one-time pointer instead of a crash notice, and a ruby-lsp
        -- installed in the project toolchain (`gem install ruby-lsp`) wins
        -- on PATH and attaches normally with upstream behavior.
        ruby_lsp = {
          root_dir = function(bufnr, on_dir)
            local fname = vim.api.nvim_buf_get_name(bufnr)
            local root = vim.fs.root(fname, { "Gemfile", ".git" })
            local exe = vim.fn.exepath "ruby-lsp"
            local nix_fallback = exe == "" or exe:find("/nix/store/", 1, true) or exe:find("/.nix-profile/", 1, true)
            if nix_fallback and root and vim.uv.fs_stat(vim.fs.joinpath(root, "Gemfile")) then
              vim.notify_once(
                (
                  "ruby_lsp: %s is a bundler project but only the Nix fallback ruby-lsp is on PATH; skipping "
                  .. "(composed bundles need the project's own Ruby). For full support install it into the "
                  .. "project toolchain: `gem install ruby-lsp`. Treesitter highlighting is still active."
                ):format(root),
                vim.log.levels.WARN
              )
              return
            end
            on_dir(root or vim.fs.dirname(fname))
          end,
        },
        -- nixpkgs elixir-ls installs `elixir-ls`; lspconfig ships no usable
        -- default cmd (upstream distributes a language_server.sh).
        elixirls = { cmd = { "elixir-ls" } },

        -- lspconfig's default filetypes include c/cpp/objc — keep sourcekit out
        -- of clangd territory.
        sourcekit = { filetypes = { "swift", "objc", "objcpp" } },

        yamlls = {
          settings = {
            yaml = {
              -- schemaStore is on by default and matches docker-compose, GitHub
              -- Actions, CloudFormation templates (*.cf.yaml etc.) by filename.
              schemas = {
                -- yamlls' built-in Kubernetes schema, scoped to conventional
                -- k8s paths so it doesn't claim every YAML file.
                kubernetes = {
                  "k8s/**/*.{yml,yaml}",
                  "kubernetes/**/*.{yml,yaml}",
                  "manifests/**/*.{yml,yaml}",
                  "*.k8s.{yml,yaml}",
                },
              },
              -- CloudFormation intrinsic-function short forms; without these
              -- yamlls flags every !Ref/!Sub as an unknown tag error.
              customTags = {
                "!And sequence",
                "!Base64 scalar",
                "!Cidr sequence",
                "!Condition scalar",
                "!Equals sequence",
                "!FindInMap sequence",
                "!GetAtt scalar",
                "!GetAtt sequence",
                "!GetAZs scalar",
                "!If sequence",
                "!ImportValue scalar",
                "!Join sequence",
                "!Not sequence",
                "!Or sequence",
                "!Ref scalar",
                "!Select sequence",
                "!Split sequence",
                "!Sub scalar",
                "!Sub sequence",
                "!Transform mapping",
              },
            },
          },
        },
      })

      return opts
    end,
  },
}
