-- Re-run a previous shell command from a terminal buffer.
--
-- Alt+r types Up, Enter (run the last command again). Alt+Shift+r types Up,
-- Up, Enter (run the one before it). Only in terminal (insert) mode.
--
-- If the last command was `clear`/`cls`, Alt+r would just clear again. So when
-- the screen is empty apart from the prompt (which is what `clear` leaves),
-- one extra Up is sent to step over it. This reads the terminal's own screen,
-- not a history file, so it follows this terminal's shell session (a history
-- file is shared by every open shell and is written late by bash).
--
-- Needs rift.term_send (rift's lua-term-send branch).
local M = {}
local MODULE = ...

local UP = "\27[A"
local ENTER = "\r"

local defaults = {
  -- Alt+r: run the previous command.
  key = "<A-r>",
  -- Alt+Shift+r: run the command before that. false to disable either key.
  key_back2 = "<A-S-r>",
  -- Step over a `clear` when the screen shows nothing but the prompt.
  skip_clear = true,
}

local skip_clear = defaults.skip_clear

-- After `clear`, the screen holds one non-blank line: the new prompt.
local function screen_was_cleared()
  local count = rift.get_line_count()
  local nonblank = 0
  for _, line in ipairs(rift.get_lines(1, count)) do
    if line:match("%S") then
      nonblank = nonblank + 1
      if nonblank > 1 then return false end
    end
  end
  return true
end

-- Run the command `n` entries back in the shell's history.
function M.rerun(n)
  if rift.buf_kind() ~= "terminal" then return end
  if not rift.term_send then
    rift.notify("error", "rift-rerun: this rift has no rift.term_send")
    return
  end
  n = n or 1
  if skip_clear and screen_was_cleared() then n = n + 1 end
  rift.term_send(UP:rep(n) .. ENTER)
end

-- Run the command through `:lua` so rift refreshes the screen lines the
-- plugin reads first (a mapped `editor:run:Command` sees stale state).
local function map(keys, name)
  rift.map("t", keys, string.format("editor:run:lua _rift_commands[%q].fn({})", name))
end

function M.setup(opts)
  opts = opts or {}
  if opts.skip_clear ~= nil then skip_clear = opts.skip_clear end
  local key = opts.key
  if key == nil then key = defaults.key end
  local key_back2 = opts.key_back2
  if key_back2 == nil then key_back2 = defaults.key_back2 end

  rift.register_command("TermRerun", function() M.rerun(1) end,
    "Terminal: run the previous command again")
  rift.register_command("TermRerun2", function() M.rerun(2) end,
    "Terminal: run the command before the previous one")
  if key then map(key, "TermRerun") end
  if key_back2 then map(key_back2, "TermRerun2") end
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
