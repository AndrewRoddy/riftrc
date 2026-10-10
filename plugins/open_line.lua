-- `o` opens a new line below with the same indentation as the current line.
--
-- rift's built-in `o` starts the new line at column 0. This runs the built-in
-- (so the insert stays one undo step) and then types the current line's
-- leading whitespace, tabs and spaces exactly as they are.
local M = {}

function M.open_below()
  local indent = ""
  if rift.buf_kind() == "file" then
    indent = rift.get_current_line():match("^[ \t]*")
  end
  rift.exec_action("mode:open_line_below")
  if indent ~= "" then rift.insert(indent) end
end

function M.setup()
  rift.register_command("OpenLineBelow", M.open_below,
    "Open a line below, keeping the current line's indentation")
  rift.map("n", "o", "editor:run:OpenLineBelow")
end

return M
