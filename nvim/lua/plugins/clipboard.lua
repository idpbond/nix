-- OSC52 clipboard provider that works through zellij in SSH sessions.
-- zellij intercepts OSC52 from child processes and doesn't forward it to the
-- outer terminal, breaking remote yank → local clipboard. Bypass: write the
-- OSC52 sequence directly to $SSH_TTY, which is the raw SSH PTY and sits
-- outside zellij's interception layer. Alacritty receives it and sets the
-- local macOS clipboard. Paste via Cmd+V back into any remote pane.
-- Locally (no $SSH_TTY), OSC52 goes to stdout; zellij 0.44.1+ forwards it.

---@type LazySpec
return {
  {
    "AstroNvim/astrocore",
    init = function()
      local function osc52_write(text)
        local encoded = vim.base64.encode(text)
        local seq = ("\027]52;c;%s\007"):format(encoded)
        local ssh_tty = os.getenv "SSH_TTY"
        if ssh_tty then
          local f = io.open(ssh_tty, "w")
          if f then
            f:write(seq)
            f:close()
          end
        else
          io.write(seq)
          io.flush()
        end
      end

      local function copy(lines, _regtype)
        osc52_write(table.concat(lines, "\n"))
      end

      local function paste()
        if vim.fn.has "mac" == 1 then
          return vim.split(vim.fn.system "pbpaste", "\n", { plain = true })
        end
        return {}
      end

      vim.g.clipboard = {
        name = "osc52",
        copy = { ["+"] = copy, ["*"] = copy },
        paste = { ["+"] = paste, ["*"] = paste },
        cache_enabled = 0,
      }
      vim.opt.clipboard = "unnamedplus"
    end,
  },
}
