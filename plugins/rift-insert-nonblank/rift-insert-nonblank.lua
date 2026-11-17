-- rift-insert-nonblank: Neovim's `I`. rift's `I` starts inserting at
-- column 0, before the indent; Neovim's starts at the first non-blank
-- character (the end of a line that is only whitespace). `gI` keeps
-- inserting at column 0.
local MODULE = ...
local M = {}

local opts = { mappings = true }

function M.insert()
  -- Visual mode falls back to Normal-mode keys, so its `I` lands here too.
  -- rift's own `I` inserts on every selected line there: leave it to rift,
  -- along with special buffers (terminal, explorer, ...).
  local kind = rift.buf_kind()
  if rift.get_mode() ~= "normal" or (kind ~= "file" and kind ~= "scratch") then
    rift.exec_action("mode:insert_line_start")
    return
  end
  local row = rift.get_cursor()
  local line = rift.get_lines(row, row)[1] or ""
  rift.set_cursor(row, #line:match("^%s*")) -- %s is ASCII: bytes == chars
  rift.exec_action("mode:insert")
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end
  rift.register_command("InsertNonblank", M.insert,
    "Insert before the first non-blank character of the line")
  if opts.mappings then
    rift.map("n", "I", "editor:run:lua _rift_commands.InsertNonblank.fn({})")
    rift.map("n", "gI", "mode:insert_line_start")
  end
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
