-- Local macOS: vim.opt.clipboard = "unnamedplus" is enough — Neovim detects
-- pbcopy/pbpaste automatically. No custom provider needed.
--
-- SSH session: Neovim's built-in provider can't reach the local clipboard
-- through zellij's PTY layer. Override with OSC52 written directly to
-- $SSH_TTY, which bypasses zellij and reaches the local Alacritty.

local ssh_tty = os.getenv "SSH_TTY"

if ssh_tty then
  local function copy(lines, _regtype)
    local encoded = vim.base64.encode(table.concat(lines, "\n"))
    local f = io.open(ssh_tty, "w")
    if f then
      f:write(("\027]52;c;%s\007"):format(encoded))
      f:close()
    end
  end
  vim.g.clipboard = {
    name = "osc52-ssh",
    copy  = { ["+"] = copy, ["*"] = copy },
    paste = { ["+"] = function() return {} end, ["*"] = function() return {} end },
    cache_enabled = 0,
  }
end

vim.opt.clipboard = "unnamedplus"
