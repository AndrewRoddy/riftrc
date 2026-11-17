-- rift-jumplist: Neovim's jump list. `<C-o>` goes back to where the cursor
-- was before a jump, `<C-i>` (or `<Tab>`, which terminals send for it) goes
-- forward again.
--
-- rift has no jump list and plugins never see which key moved the cursor,
-- so a jump is a move of `min_lines` or more lines at once (G, gg, /, n, %,
-- {, }, gd, ...) or into another buffer. Moves in Insert mode don't count.
--
-- rift doesn't send CursorMoved for some moves (G, gg, searches, L, <C-d>),
-- so the cursor is also compared with where it last was whenever anything
-- else happens: <C-o> / <C-i>, CursorHold, a mode change, an edit.
local MODULE = ...
local M = {}

local opts = {
  back = "<C-o>",
  forward = { "<C-i>", "<Tab>" },
  min_lines = 2,  -- a move of at least this many lines is a jump
  max = 100,      -- positions kept
}

-- Positions are { buf, row, col }: row 1-indexed, col 0-indexed.
local list = {}  -- oldest first
local idx = 1    -- where <C-o> / <C-i> are in `list`; #list + 1 at the newest
local prev       -- the cursor as of the last move seen
local expect     -- where our own <C-o> / <C-i> is moving the cursor

local function pos(buf, row, col) return { buf = buf, row = row, col = col } end

local function here()
  local row, col = rift.get_cursor()
  return pos(rift.current_buf(), row, col)
end

local function same_line(a, b) return a.buf == b.buf and a.row == b.row end
local function same_pos(a, b) return same_line(a, b) and a.col == b.col end

local function buf_index(buf)
  for i, b in ipairs(rift.get_buf_list()) do
    if b.id == buf then return i end
  end
end

-- Neovim's setpcmark: drop older entries for the same line, then append.
local function record(p)
  for i = #list, 1, -1 do
    if same_line(list[i], p) then table.remove(list, i) end
  end
  list[#list + 1] = pos(p.buf, p.row, p.col)
  while #list > opts.max do table.remove(list, 1) end
  idx = #list + 1
end

-- A cursor move: if it was a jump, remember where it started. `any_mode`
-- counts it whatever the mode is now (a search or `:` that moved it).
local function moved(p, any_mode)
  if expect then
    local ours = same_line(expect, p)
    expect = nil
    if ours then prev = p return end
  end
  local mode = rift.get_mode()
  if prev and (any_mode or mode == "normal" or mode == "visual")
    and (prev.buf ~= p.buf or math.abs(prev.row - p.row) >= opts.min_lines) then
    record(prev)
  end
  prev = p
end

-- Catch up on a move rift didn't report.
local function sync(any_mode)
  local cur = here()
  if not prev or not same_pos(prev, cur) then moved(cur, any_mode) end
end

local function go(p)
  local cur = here()
  local row = p.row
  if p.buf ~= cur.buf then
    -- rift.switch_buf changes the active buffer but not what the window
    -- shows; `:buffer N` (N = place in the buffer list) does both.
    rift.exec_action("editor:run:buffer " .. buf_index(p.buf))
  else
    -- Lines may have been deleted since the jump was recorded.
    row = math.min(row, math.max(rift.get_line_count(), 1))
  end
  local target = pos(p.buf, row, p.col)
  if not same_pos(target, cur) then expect = target end
  rift.set_cursor(row, p.col)
  prev = target
end

local function usable(p, cur)
  return buf_index(p.buf) ~= nil and not same_line(p, cur)
end

function M.back()
  sync()
  local cur = here()
  if idx > #list then
    -- Leaving the newest position: remember it so <C-i> can come back.
    record(cur)
    idx = #list
  end
  local i = idx - 1
  while i >= 1 and not usable(list[i], cur) do i = i - 1 end
  if i < 1 then return end
  idx = i
  go(list[i])
end

function M.forward()
  sync()
  local cur = here()
  local i = idx + 1
  while i <= #list and not usable(list[i], cur) do i = i + 1 end
  if i > #list then return end
  idx = i
  go(list[i])
end

function M.jumps()
  if #list == 0 then
    rift.notify("info", "Jump list is empty")
    return
  end
  local names = {}
  for _, b in ipairs(rift.get_buf_list()) do names[b.id] = b.name or tostring(b.id) end
  local out = {}
  for i, p in ipairs(list) do
    out[#out + 1] = string.format("%s %3d  %d:%d  %s", i == idx and ">" or " ",
      math.abs(i - idx), p.row, p.col, names[p.buf] or "(closed)")
  end
  if idx > #list then out[#out + 1] = ">" end
  rift.notify("info", table.concat(out, "\n"))
end

local function map(keys, cmd)
  if not keys then return end
  if type(keys) == "string" then keys = { keys } end
  for _, k in ipairs(keys) do
    rift.map("n", k, "editor:run:lua _rift_commands." .. cmd .. ".fn({})")
  end
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end
  rift.register_command("JumpBack", M.back, "Go to the previous jump position")
  rift.register_command("JumpForward", M.forward, "Go to the next jump position")
  rift.register_command("Jumps", M.jumps, "Show the jump list")
  map(opts.back, "JumpBack")
  map(opts.forward, "JumpForward")

  local function start()
    if not prev then prev = here() end
  end
  rift.on("EditorStart", start)
  rift.on("CursorMoved", function(ev) moved(pos(ev.buf, ev.row, ev.col)) end)
  -- (sync is wrapped so the event table isn't taken for `any_mode`.)
  rift.on("CursorHold", function() sync() end)
  rift.on("TextChangedCoarse", function() sync() end)
  -- Switching buffers doesn't always move the cursor.
  rift.on("BufEnter", function()
    if prev then sync() else start() end
  end)
  rift.on("ModeChanged", function(ev)
    -- Moves made while typing text don't count; a search or a `:` command
    -- that moved the cursor does.
    if ev.from == "insert" or ev.from == "replace" then
      prev = here()
    else
      sync(true)
    end
  end)
  rift.on("BufClose", function(ev)
    for i = #list, 1, -1 do
      if list[i].buf == ev.buf then
        table.remove(list, i)
        if i < idx then idx = idx - 1 end
      end
    end
    idx = math.min(idx, #list + 1)
  end)
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
