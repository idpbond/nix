return {
  { "EdenEast/nightfox.nvim" },
  { "ellisonleao/gruvbox.nvim" },
  { "WTFox/jellybeans.nvim" },
  { "bluz71/vim-moonfly-colors" },
  { "tiagovla/tokyodark.nvim" },
  { "ribru17/bamboo.nvim" },
  {
    "AstroNvim/astroui",
    ---@type AstroUIOpts
    opts = {
      colorscheme = "moonfly",
    },
  },
  {
    event = { "VeryLazy" },
    url = "https://codeberg.org/andyg/leap.nvim",
    keys = {
      { "<Plug>(leap-forward-to)",  mode = { "n", "x", "o" } },
      { "<Plug>(leap-backward-to)", mode = { "n", "x", "o" } },
      { "<Plug>(leap-from-window)", mode = { "n", "x", "o" } },
    },
    config = function(_, opts)
      local leap = require("leap")
      for k, v in pairs(opts) do
        leap.opts[k] = v
      end
      vim.keymap.set({ "n", "x", "o" }, ",s", "<Plug>(leap-forward-to)", { desc = "Leap forward" })
      vim.keymap.set({ "n", "x", "o" }, ",S", "<Plug>(leap-backward-to)", { desc = "Leap backward" })
      vim.keymap.set({ "n", "x", "o" }, "gs", "<Plug>(leap-from-window)", { desc = "Leap from window" })
    end,
  },
  {
    "AstroNvim/astrocore",
    ---@type AstroCoreOpts
    opts = {
      mappings = {
        n = {
          ["<c-j>"] = { "<cmd>bn<cr>", desc = "Next Buffer" },
          ["<c-k>"] = { "<cmd>bp<cr>", desc = "Prev Buffer" },
          ["<Leader>wc"] = { "<cmd>wincmd c<cr>", desc = "Close" },
          ["<Leader>ws"] = { "<cmd>split<cr>", desc = "Split" },
          ["<Leader>wv"] = { "<cmd>vsplit<cr>", desc = "Split (Vertical)" },
          ["<Leader>wh"] = { "<cmd>wincmd h<cr>", desc = "Pane Left" },
          ["<Leader>wj"] = { "<cmd>wincmd j<cr>", desc = "Pane Down" },
          ["<Leader>wk"] = { "<cmd>wincmd k<cr>", desc = "Pane Up" },
          ["<Leader>wl"] = { "<cmd>wincmd l<cr>", desc = "Pane Right" },
          ["<Leader>wL"] = { "<cmd>wincmd 15><cr>", desc = "Increase Size" },
          ["<Leader>wH"] = { "<cmd>wincmd 15<<cr>", desc = "Decrease Size" },
          ["<Leader>gw"] = { "<cmd>lua require 'gitsigns'.toggle_word_diff()<cr>", desc = "Toggle Word Diff" },
          ["<Leader>gj"] = { "<cmd>lua require 'gitsigns'.next_hunk()<cr>", desc = "Next Hunk" },
          ["<Leader>gk"] = { "<cmd>lua require 'gitsigns'.prev_hunk()<cr>", desc = "Prev Hunk" },
          ["<Leader>gx"] = function()
            local buffers = vim.api.nvim_list_bufs()
            local filtered_buffers = {}
            for _, buffer in ipairs(buffers) do
              local name = vim.api.nvim_buf_get_name(buffer)
              if name:sub(1, 11) == "gitsigns://" then
                table.insert(filtered_buffers, buffer)
              end
            end
            if #filtered_buffers == 0 then
              require("gitsigns").diffthis()
            else
              for _, buffer in ipairs(filtered_buffers) do
                vim.api.nvim_buf_delete(buffer, {})
              end
            end
          end,
        },
      },
    },
  },
  -- {
  --   "yetone/avante.nvim",
  --   event = "VeryLazy",
  --   build = "make", -- This is Optional, only if you want to use tiktoken_core to calculate tokens count
  --   opts = {
  --     mode = "agentic",
  --     provider = "openai",
  --     -- provider = "gemini",
  --     providers = {
  --       openai = {
  --         model = "gpt-4.1", -- The model name to use with this provider
  --         -- api_key_name = "OPENAI_API_KEY", -- The name of the environment variable that contains the API key
  --       },
  --       bedrock = {
  --         model = "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
  --         timeout = 30000, -- Timeout in milliseconds
  --       },
  --       gemini = {
  --         model = "gemini-2.5-pro-preview-05-06",
  --         timeout = 30000, -- Timeout in milliseconds
  --         -- temperature = 0,
  --         -- max_tokens = 8192,
  --       },
  --     },
  --   },
  --   dependencies = {
  --     "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
  --     "stevearc/dressing.nvim",
  --     "nvim-lua/plenary.nvim",
  --     "MunifTanjim/nui.nvim",
  --     --- The below is optional, make sure to setup it properly if you have lazy=true
  --     {
  --       "MeanderingProgrammer/render-markdown.nvim",
  --       opts = {
  --         file_types = { "markdown", "Avante" },
  --       },
  --       ft = { "markdown", "Avante" },
  --     },
  --   },
  -- },
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    config = true,
    keys = {
      { "<leader>a",  nil,                              desc = "AI/Claude Code" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>",            desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",       desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>",   desc = "Resume Claude" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",       desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>",        mode = "v",                  desc = "Send to Claude" },
      {
        "<leader>as",
        "<cmd>ClaudeCodeTreeAdd<cr>",
        desc = "Add file",
        ft = { "NvimTree", "neo-tree", "oil", "minifiles" },
      },
      -- Diff management
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",   desc = "Deny diff" },
    },
  },

  {
    "rebelot/heirline.nvim",
    opts = function(_, opts)
      local status = require("astroui.status")
      local path_func = status.provider.filename({ modify = ":.", fallback = "" })

      opts.statusline = { -- statusline
        hl = { fg = "fg", bg = "bg" },
        status.component.mode(),
        status.component.git_branch(),
        status.component.file_info(),
        status.component.git_diff(),
        status.component.diagnostics(),
        {
          status.component.separated_path({
            path_func = path_func,
            separator = "/",
            suffix = false,
            max_depth = 10,
          }),
          hl = { fg = "gray" },
        },
        status.component.fill(),
        status.component.cmd_info(),
        status.component.fill(),
        status.component.lsp(),
        status.component.virtual_env(),
        status.component.treesitter(),
        status.component.nav(),
        status.component.mode({ surround = { separator = "right" } }),
      }

      opts.winbar = nil

      opts.tabline = { -- tabline
        {           -- file tree padding
          condition = function(self)
            self.winid = vim.api.nvim_tabpage_list_wins(0)[1]
            self.winwidth = vim.api.nvim_win_get_width(self.winid)
            return self.winwidth ~= vim.o.columns                                         -- only apply to sidebars
                and not require("astrocore.buffer").is_valid(vim.api.nvim_win_get_buf(self.winid)) -- if buffer is not in tabline
          end,
          provider = function(self)
            return (" "):rep(self.winwidth + 1)
          end,
          hl = { bg = "tabline_bg" },
        },
        status.heirline.make_buflist(status.component.tabline_file_info()), -- component for each buffer tab
        status.component.fill({ hl = { bg = "tabline_bg" } }),          -- fill the rest of the tabline with background color
        {                                                               -- tab list
          condition = function()
            return #vim.api.nvim_list_tabpages() >= 2
          end,                      -- only show tabs if there are more than one
          status.heirline.make_tablist({ -- component for each tab
            provider = status.provider.tabnr(),
            hl = function(self)
              return status.hl.get_attributes(status.heirline.tab_type(self, "tab"), true)
            end,
          }),
          { -- close button for current tab
            provider = status.provider.close_button({
              kind = "TabClose",
              padding = { left = 1, right = 1 },
            }),
            hl = status.hl.get_attributes("tab_close", true),
            on_click = {
              callback = function()
                require("astrocore.buffer").close_tab()
              end,
              name = "heirline_tabline_close_tab_callback",
            },
          },
        },
      }

      opts.statuscolumn = { -- statuscolumn
        init = function(self)
          self.bufnr = vim.api.nvim_get_current_buf()
        end,
        status.component.foldcolumn(),
        status.component.numbercolumn(),
        status.component.signcolumn(),
      }
    end,
  },
  {
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = {
      formatting = {
        disabled = { -- disable formatting capabilities for the listed language servers
          -- disable lua_ls formatting capability if you want to use StyLua to format your lua code
          "ts_ls",
          -- "tailwindcss",
          "eslint",
          -- "prettier"
        },
        timeout_ms = 5000, -- default format timeout
        -- filter = function(client) -- fully override the default formatting function
        --   return true
        -- end
      },
      ---@diagnostic disable: missing-fields
      config = {
        -- add support for class-variance-authority+tailwind usage
        tailwindcss = {
          settings = {
            tailwindCSS = {
              experimental = {
                classRegex = {
                  { "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
                  { "cx\\(([^)]*)\\)",  "[\"'`]([^\"'`]*).*?[\"'`]" },
                },
              },
            },
          },
        },
      },
    },
  },
}
