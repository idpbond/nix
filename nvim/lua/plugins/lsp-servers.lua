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

      opts.config = require("astrocore").extend_tbl(opts.config, {
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
