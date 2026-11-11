-- `o` opens a new line below with the same indentation as the current line.
--
-- rift's built-in `o` starts the new line at column 0. This runs the built-in
-- (so the insert stays one undo step) and then types the current line's
-- leading whitespace, tabs and spaces exactly as they are.
local M = {}
local MODULE = ...

-- Helpers -------------------------------------------------------------------

local function current_line()
  local row = rift.get_cursor()
  return rift.get_lines(row, row)[1] or ""
end

-- Keymaps run the command through `:lua`: rift refreshes what plugins read
-- (cursor, lines, mode) right before `:lua`, but not before a mapped
-- `editor:run:Command`, which would see the cursor from before the last
-- motion. _rift_commands is rift's table of registered plugin commands.
local function map(mode, keys, cmdline)
  local name, rest = cmdline:match("^(%S+)%s*(.*)$")
  local args = {}
  for a in rest:gmatch("%S+") do args[#args + 1] = string.format("%q", a) end
  rift.map(mode, keys, string.format("editor:run:lua _rift_commands[%q].fn({ %s })",
    name, table.concat(args, ", ")))
end

-----------------------------------------------------------------------------

function M.open_below()
  local indent = ""
  if rift.buf_kind() == "file" then
    indent = current_line():match("^[ \t]*")
  end
  rift.exec_action("mode:open_line_below")
  if indent ~= "" then rift.insert(indent) end
end

function M.setup()
  rift.register_command("OpenLineBelow", M.open_below,
    "Open a line below, keeping the current line's indentation")
  map("n", "o", "OpenLineBelow")
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
