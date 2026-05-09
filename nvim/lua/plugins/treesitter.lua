-- Treesitter is configured via AstroCore. Parsers themselves come from Nix
-- (see modules/neovim.nix → parserLanguages), so we explicitly disable
-- nvim-treesitter's runtime auto-install — the parser dir is a read-only
-- store symlink and writes there fail with EACCES.

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    treesitter = {
      highlight = true,
      indent = true,
      auto_install = false,
      ensure_installed = {}, -- managed by Nix
    },
  },
}
