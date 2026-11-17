-- rift-jumplist: Neovim's jump list. `<C-o>` goes back to where the cursor
-- was before a jump, `<C-i>` (or `<Tab>`, which terminals send for it) goes
-- forward again.
--
-- rift has no jump list and plugins never see which key moved the cursor,
-- so a jump is a cursor move of more than one line at once (G, gg, /, n,
-- %, {, }, gd, ...) or into another buffer. Moves in Insert mode don't count.
--
-- rift doesn't send CursorMoved for some of them (G, gg, searches, L,
-- <C-d>), so the cursor is also compared with where it last was whenever
-- anything else happens: <C-o> / <C-i>, CursorHold, a mode change, an edit.
local MODULE = ...
local M = {}

local opts = {
  back = "<C-o>",
  forward = { "<C-i>", "<Tab>" },
  min_lines = 2,   -- a move of at least this many lines is a jump
  max = 100,       -- entries kept
}

local list = {}      -- { buf, row, col }, oldest first
local idx = 1        -- #list + 1 when not navigating the list
local prev           -- the cursor before the latest move: { buf, row, col }
local expect         -- where our own <C-o>/<C-i> is moving the cursor

local function here()
  local row, col = rift.get_cursor()
  return { buf = rift.current_buf(), row = row, col = col }
end

local function same_line(a, b) return a.buf == b.buf and a.row == b.row end

local function buf_exists(buf)
  for _, b in ipairs(rift.get_buf_list()) do
    if b.id == buf then return true end
  end
  return false
end

-- Neovim's setpcmark: drop older entries for the same line, then append.
local function record(pos)
  for i = #list, 1, -1 do
    if same_line(list[i], pos) then table.remove(list, i) end
  end
  list[#list + 1] = { buf = pos.buf, row = pos.row, col = pos.col }
  while #list > opts.max do table.remove(list, 1) end
  idx = #list + 1
end

local function go(pos)
  local cur = here()
  if pos.buf ~= cur.buf then
    -- rift.switch_buf changes the active buffer but not what the window
    -- shows; `:buffer N` (N = place in the buffer list) does both.
    for i, b in ipairs(rift.get_buf_list()) do
      if b.id == pos.buf then rift.exec_action("editor:run:buffer " .. i) break end
    end
  end
  -- Lines may have been deleted since the jump was recorded.
  local count = pos.buf == cur.buf and rift.get_line_count() or nil
  local row = count and math.min(pos.row, math.max(count, 1)) or pos.row
  if pos.buf ~= cur.buf or row ~= cur.row or pos.col ~= cur.col then
    expect = { buf = pos.buf, row = row, col = pos.col }
  end
  rift.set_cursor(row, pos.col)
  prev = { buf = pos.buf, row = row, col = pos.col }
end

local function usable(pos, cur)
  return buf_exists(pos.buf) and not same_line(pos, cur)
end

local function moved(pos, any_mode)
  if expect then
    local ours = expect.buf == pos.buf and expect.row == pos.row
    expect = nil
    if ours then prev = pos return end
  end
  local mode = rift.get_mode()
  if prev and (any_mode or mode == "normal" or mode == "visual") then
    if prev.buf ~= pos.buf or math.abs(prev.row - pos.row) >= opts.min_lines then
      record(prev)
    end
  end
  prev = pos
end

-- Catch up on a move rift didn't report.
local function sync(any_mode)
  local cur = here()
  if not prev or prev.buf ~= cur.buf or prev.row ~= cur.row or prev.col ~= cur.col then
    moved(cur, any_mode)
  end
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
  for i, pos in ipairs(list) do
    out[#out + 1] = string.format("%s %3d  %d:%d  %s", i == idx and ">" or " ",
      math.abs(i - idx), pos.row, pos.col, names[pos.buf] or "(closed)")
  end
  if idx > #list then out[#out + 1] = ">" end
  rift.notify("info", table.concat(out, "\n"))
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end
  rift.register_command("JumpBack", function() M.back() end, "Go to the previous jump position")
  rift.register_command("JumpForward", function() M.forward() end, "Go to the next jump position")
  rift.register_command("Jumps", function() M.jumps() end, "Show the jump list")
  local function map(keys, cmd)
    if not keys then return end
    if type(keys) == "string" then keys = { keys } end
    for _, k in ipairs(keys) do
      rift.map("n", k, "editor:run:lua _rift_commands." .. cmd .. ".fn({})")
    end
  end
  map(opts.back, "JumpBack")
  map(opts.forward, "JumpForward")

  rift.on("CursorMoved", function(ev)
    moved({ buf = ev.buf, row = ev.row, col = ev.col })
  end)
  -- Switching buffers doesn't always move the cursor.
  rift.on("BufEnter", function()
    local pos = here()
    if not prev then prev = pos elseif prev.buf ~= pos.buf then moved(pos) end
  end)
  rift.on("CursorHold", function() sync() end)
  rift.on("TextChangedCoarse", function() sync() end)
  rift.on("ModeChanged", function(ev)
    -- Moves made while typing text don't count; a search or a `:` command
    -- that moved the cursor does.
    if ev.from == "insert" or ev.from == "replace" then
      prev = here()
    else
      sync(true)
    end
  end)
  rift.on("EditorStart", function()
    if not prev then prev = here() end
  end)
  rift.on("BufClose", function(ev)
    for i = #list, 1, -1 do
      if list[i].buf == ev.buf then
        table.remove(list, i)
        if i < idx then idx = idx - 1 end
      end
    end
    if idx > #list + 1 then idx = #list + 1 end
  end)
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
