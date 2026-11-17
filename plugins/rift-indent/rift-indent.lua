-- Neovim-style `>>` / `<<` line shifting, plus `>` / `<` in visual mode.
local M = {}
local MODULE = ...

-- Helpers -------------------------------------------------------------------

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

local opts = {
  shiftwidth = nil, -- nil follows the buffer's tab_width
  mappings = true,
  reselect = true, -- keep the selection after visual `>` / `<`, like `>gv`
}

local function shiftwidth()
  return opts.shiftwidth or rift.get_tab_width()
end

local function is_white(c)
  return c == " " or c == "\t"
end

-- Columns `c` takes up when it starts at virtual column `vcol`.
local function width(c, vcol, ts)
  if c == "\t" then return ts - vcol % ts end
  return 1
end

-- The line as an array of characters, so columns match rift's char columns.
local function chars_of(line)
  local out = {}
  local ok = pcall(function()
    for _, cp in utf8.codes(line) do out[#out + 1] = utf8.char(cp) end
  end)
  if not ok then
    out = {}
    for c in line:gmatch(".") do out[#out + 1] = c end
  end
  return out
end

-- Virtual column where character `col` (0-indexed) starts, and its width.
local function vcol_at(chars, col, ts)
  local v = 0
  for i = 1, math.min(col, #chars) do v = v + width(chars[i], v, ts) end
  if col >= #chars then return v + col - #chars, 1 end
  return v, width(chars[col + 1], v, ts)
end

-- The column vim's curswant holds for a cursor on character `col`: a tab
-- counts as its last screen column, unless `tab_start` is set.
local function cursor_vcol(line, col, ts, tab_start)
  local chars = chars_of(line)
  local v, w = vcol_at(chars, col, ts)
  if chars[col + 1] == "\t" and not tab_start then return v + w - 1 end
  return v
end

-- vim's coladvance() in Normal mode: the character covering virtual column
-- `want`, or the last character when the line is shorter.
local function coladvance(line, want, ts)
  local chars = chars_of(line)
  local v = 0
  for i, c in ipairs(chars) do
    local w = width(c, v, ts)
    if v + w > want then return i - 1 end
    v = v + w
  end
  return math.max(0, #chars - 1)
end

-- Whitespace that spans `total` columns starting at virtual column `vcol`,
-- honouring expandtab.
local function make_ws(vcol, total, ts, expand)
  if expand then return string.rep(" ", total) end
  local tabs = ((vcol % ts) + total) // ts
  if tabs == 0 then return string.rep(" ", total) end
  return string.rep("\t", tabs) .. string.rep(" ", ((vcol % ts) + total) % ts)
end

-- Shifts one line `dir` shiftwidths (+1 right, -1 left), rebuilding the whole
-- indent. Empty lines stay empty, like vim.
local function shift_line(line, dir, sw, ts, expand)
  if line == "" then return line end
  local ws, body = line:match("^([ \t]*)(.*)$")
  local w = 0
  for c in ws:gmatch(".") do w = w + width(c, w, ts) end
  return make_ws(0, math.max(0, w + dir * sw), ts, expand) .. body
end

-- vim's shift_block() for one line of a blockwise selection whose left edge
-- is virtual column `left`. Lines that end before the block are untouched.
local function shift_block_line(line, dir, left, sw, ts, expand)
  local ch = chars_of(line)
  local n = #ch

  -- Walk to the block's edge, tracking the whitespace run right before it.
  local v, i, last_w = 0, 1, 0
  local pre_ws, pre_ws_c = 0, 0
  while v < left and i <= n do
    local w = width(ch[i], v, ts)
    if is_white(ch[i]) then
      pre_ws, pre_ws_c = pre_ws + w, pre_ws_c + 1
    else
      pre_ws, pre_ws_c = 0, 0
    end
    v, last_w, i = v + w, w, i + 1
  end
  -- As in Neovim: empty lines and lines that end before the block are left
  -- alone; a line that ends right at the block's edge gets the shift added
  -- at its end by `>` (with any whitespace it already ends in).
  if n == 0 or v < left then return line end
  if i > n and v == left then
    if dir < 0 then return line end
    return table.concat(ch, "", 1, n - pre_ws_c) .. make_ws(v - pre_ws, sw + pre_ws, ts, expand)
  end
  -- A tab straddling the edge leaves `v` past it; ch[i - 1] is that tab.
  local split = v > left

  -- First non-white character at or after the edge.
  local j, jv = i, v
  while j <= n and is_white(ch[j]) do
    jv = jv + width(ch[j], jv, ts)
    j = j + 1
  end
  local tail = table.concat(ch, "", j, n)

  if dir > 0 then
    -- The whitespace around the edge is rebuilt one shiftwidth wider.
    local ws_vcol = v - pre_ws
    local total = sw + pre_ws + (jv - v)
    return table.concat(ch, "", 1, i - 1 - pre_ws_c) .. make_ws(ws_vcol, total, ts, expand) .. tail
  end

  -- Remove up to a shiftwidth of the whitespace that starts at the edge.
  local dest = jv - math.min(jv - left, sw)
  local k, kv = i, v
  if split then k, kv = i - 1, v - last_w end
  while kv < dest do
    local w = width(ch[k], kv, ts)
    if kv + w > dest then break end
    kv, k = kv + w, k + 1
  end
  return table.concat(ch, "", 1, k - 1) .. string.rep(" ", dest - kv) .. tail
end

local function shift_lines(lines, dir)
  local sw, ts, expand = shiftwidth(), rift.get_tab_width(), rift.get_expand_tabs()
  local out = {}
  for i, line in ipairs(lines) do out[i] = shift_line(line, dir, sw, ts, expand) end
  return out
end

local function editable()
  if rift.buf_kind() ~= "file" then
    rift.notify("warn", "Indent: not a file buffer")
    return false
  end
  for _, b in ipairs(rift.get_buf_list()) do
    if b.is_current and b.is_read_only then
      rift.notify("warn", "Indent: buffer is read-only")
      return false
    end
  end
  return true
end

-- rift.get_selection only exists on unreleased rift builds; on the
-- released ones (0.7.x) the Visual-mode keys go through shift_visual.
local legacy = rift.get_selection == nil

-- Mappings run through :lua (see map), which refreshes the snapshot first,
-- so the cursor and lines read here are current.
local function cursor()
  return rift.get_cursor()
end

-- Moves the cursor and makes `j` / `k` keep its column, as Neovim does after
-- undo / redo. rift.set_cursor leaves rift's remembered column alone (so `j`
-- would jump back to wherever it was); a left/right motion clears it.
local function place_cursor(row, col)
  rift.set_cursor(row, col)
  rift.exec_action("editor:move:left")
  rift.exec_action("editor:move:right")
  rift.set_cursor(row, col)
end

local function line_at(row)
  return rift.get_lines(row, row)[1] or ""
end

local function lines_in(s, e)
  local out = {}
  for row = s, e do out[#out + 1] = line_at(row) end
  return out
end

-- Rewrites line `row` from `old` to `new` by touching only the indent that
-- differs.
local function edit_indent(row, old, new)
  local old_ws = old:match("^[ \t]*")
  local new_ws = new:match("^[ \t]*")
  local p = 0
  while p < #old_ws and p < #new_ws and old_ws:byte(p + 1) == new_ws:byte(p + 1) do
    p = p + 1
  end
  rift.set_cursor(row, p)
  if #old_ws > p then rift.delete_forward(#old_ws - p) end
  if #new_ws > p then rift.insert(new_ws:sub(p + 1)) end
end

-- Replaces lines [s, e] from Normal mode, as one undo step. Only the indent
-- is edited (replace_lines joins the next line on and takes two undo steps),
-- inside a brief Insert mode: rift groups everything until Insert mode is
-- left into one undo step, while each delete outside it is its own.
--
-- A shift that changes nothing is still an undo step in Neovim (`u` after
-- it undoes nothing visible), so then a space is typed and deleted.
local function replace(s, e, lines)
  rift.exec_action("mode:insert")
  local changed = false
  for i, new in ipairs(lines) do
    local row = s + i - 1
    local old = line_at(row)
    if old ~= new then
      edit_indent(row, old, new)
      changed = true
    end
  end
  if not changed then
    rift.set_cursor(s, 0)
    rift.insert(" ")
    rift.delete_before(1)
  end
  -- Redo leaves the cursor where it was when the edit ended: the start of
  -- the first line, as in Neovim.
  rift.set_cursor(s, 0)
  rift.exec_action("mode:normal")
end

-- Shifts lines [s, e] (1-indexed, inclusive). As in Neovim (nostartofline),
-- the cursor moves to line `s` and keeps its screen column.
function M.shift_range(dir, s, e)
  if not editable() then return end
  local ts = rift.get_tab_width()
  local row, col = cursor()
  local want = cursor_vcol(line_at(row), col, ts)
  local total = rift.get_line_count()
  s, e = math.max(1, math.min(s, e)), math.min(total, math.max(s, e))
  local new = shift_lines(lines_in(s, e), dir)
  replace(s, e, new)
  rift.set_cursor(s, coladvance(new[1], want, ts))
end

-- Where the live Visual selection started and its kind: rift.get_cursor()
-- as Visual mode was entered (rift refreshes the snapshot right before
-- firing ModeChanged). rift has no way for plugins to read the selection.
local visual_start -- { buf, row, col, kind = "visual"|"visualline"|"visualblock" }

-- Each shift in Visual is two undo steps (replace_lines deletes lines s..e,
-- then inserts the new ones). `u` / `<C-r>` are wrapped to take both at
-- once. A shift is only taken as such when the text matches exactly: before
-- the first step it must be what the shift left behind (or, for redo, what
-- it started from), and after that step it must be the in-between state with
-- lines s..e removed. Anything else gets the ordinary single step.
local shifts = {}    -- undoable: { buf, s, before, mid, after }
local unshifts = {}  -- redoable
local stepping       -- { sh, dir } between the two steps

local function buffer_text()
  return table.concat(rift.get_lines(1, -1), "\n")
end

-- Row (1-indexed) holding character offset `off`, counted from the start of
-- row `s`, in `lines` (rows s, s+1, ...); nil when past the last one.
local function row_of_offset(lines, s, off)
  for i, line in ipairs(lines) do
    local len = utf8.len(line) or #line
    if off <= len then return s + i - 1 end
    off = off - len - 1
  end
end

local function char_len(s) return utf8.len(s) or #s end

-- Neovim's visual `>` / `<` followed by `gv` (`vnoremap > >gv`): shift the
-- selected lines one shiftwidth and keep the same selection. Block
-- selections shift the text from the block's left edge. As in Neovim, both
-- ends keep their columns, within their (possibly shorter) lines.
--
-- rift can't re-enter Visual mode from a plugin, so the lines are rewritten
-- without leaving it. The selection's anchor is a fixed character offset
-- that edits don't move, so this only works when the anchor ends up where
-- Neovim would put it: on its own row, at its own column. Otherwise (e.g.
-- selecting upward with `Vk`) the lines are shifted and Visual mode ends.
function M.shift_visual(dir)
  if not editable() then return end
  local buf = rift.current_buf()
  local cur_row, cur_col = cursor()
  local vs = (visual_start and visual_start.buf == buf) and visual_start
    or { row = cur_row, col = cur_col, kind = "visual" }
  local s, e = math.min(vs.row, cur_row), math.max(vs.row, cur_row)
  local sw, ts, expand = shiftwidth(), rift.get_tab_width(), rift.get_expand_tabs()

  local old = lines_in(s, e)
  local new = {}
  if vs.kind == "visualblock" then
    local left = math.min(
      (vcol_at(chars_of(line_at(vs.row)), vs.col, ts)),
      (vcol_at(chars_of(line_at(cur_row)), cur_col, ts)))
    for i, line in ipairs(old) do
      new[i] = shift_block_line(line, dir, left, sw, ts, expand)
    end
  else
    for i, line in ipairs(old) do new[i] = shift_line(line, dir, sw, ts, expand) end
  end

  -- Where Neovim leaves the cursor: same column, within the line.
  local cur_line = new[cur_row - s + 1]
  local want_col = math.min(cur_col, char_len(cur_line))

  local all = rift.get_lines(1, -1)
  local count = #all
  local before = table.concat(all, "\n")

  -- Where `u` / `<C-r>` leave the cursor, as in Neovim: the start of the
  -- selection (column 0 for V, the left edge for a block) on line s.
  local ucol = 0
  if vs.kind == "visualblock" then
    ucol = math.min(vs.col, cur_col)
  elseif vs.kind ~= "visualline" then
    local anchor_first = vs.row < cur_row or (vs.row == cur_row and vs.col <= cur_col)
    ucol = anchor_first and vs.col or cur_col
  end
  ucol = math.max(0, math.min(ucol, char_len(old[1]) - 1))

  local changed = false
  for i = 1, #old do
    if old[i] ~= new[i] then changed = true break end
  end
  if not changed then
    -- Still an undo step in Neovim (`u` then undoes nothing visible): type
    -- a space at the start of line s and delete it, recorded like a shift
    -- whose in-between state has the space.
    local mid = { table.unpack(all) }
    mid[s] = " " .. mid[s]
    rift.set_cursor(s, 0)
    rift.insert(" ")
    rift.delete_before(1)
    rift.set_cursor(cur_row, want_col)
    shifts[#shifts + 1] = { buf = buf, s = s, ucol = ucol, before = before,
      mid = table.concat(mid, "\n"), after = before }
    if #shifts > 100 then table.remove(shifts, 1) end
    unshifts = {}
    return
  end

  -- The anchor's offset from the start of row s has to land on its own
  -- row, at its own column, in the new text.
  local off = vs.col
  for row = s, vs.row - 1 do
    off = off + char_len(old[row - s + 1]) + 1
  end
  if row_of_offset(new, s, off) ~= vs.row then
    -- rift-clipboard would take leaving Visual here for a `y`.
    local not_yank = _rift_commands and _rift_commands.ClipboardNotYank
    if not_yank then not_yank.fn({}) end
    rift.exec_action("mode:normal")
    rift.exec_action("mode:normal")
    M.shift_range(dir, s, e)
    return
  end

  local out = { table.unpack(new) }
  if e < count then out[#out + 1] = "" end
  -- Undo puts the cursor back where it was before the edit.
  rift.set_cursor(s, ucol)
  rift.replace_lines(s, e, out)
  -- rift.set_cursor keeps rift's remembered column for `j` / `k`, as `gv`
  -- keeps Neovim's.
  rift.set_cursor(cur_row, want_col)

  -- rift-clipboard tells a Visual `y` from a delete by the buffer's size.
  local edited = _rift_commands and _rift_commands.ClipboardVisualEdited
  if edited then
    local delta = 0
    for i = 1, #old do delta = delta + #new[i] - #old[i] end
    edited.fn({ tostring(delta) })
  end

  -- The in-between state: lines s..e deleted with their newlines (the last
  -- line has none, so the newline before it stays).
  local mid = {}
  for i = 1, s - 1 do mid[#mid + 1] = all[i] end
  if e < count then
    for i = e + 1, count do mid[#mid + 1] = all[i] end
  else
    mid[#mid + 1] = ""
  end
  for i = s, e do all[i] = new[i - s + 1] end
  shifts[#shifts + 1] = { buf = buf, s = s, ucol = ucol, before = before,
    mid = table.concat(mid, "\n"), after = table.concat(all, "\n") }
  if #shifts > 100 then table.remove(shifts, 1) end
  unshifts = {}
end

-- One undo / redo step. rift-clipboard wraps `u` / `<C-r>` to keep its `p`
-- working after an undo, so go through it when it's loaded.
local function history(dir)
  local cmd = _rift_commands and _rift_commands.ClipboardUndo
  if cmd then
    cmd.fn(dir == "redo" and { "redo" } or {})
  else
    rift.exec_action("history:" .. dir)
  end
end

-- First step of `u` / `<C-r>`. When the text is what a shift left behind
-- (undo) or started from (redo), the second step is decided by
-- IndentHistoryStep, run once the first one has been applied.
local function step(dir)
  local text, buf = buffer_text(), rift.current_buf()
  local from, key = dir == "undo" and shifts or unshifts, dir == "undo" and "after" or "before"
  stepping = nil
  for i = #from, 1, -1 do
    local sh = from[i]
    if sh.buf == buf and sh[key] == text then
      table.remove(from, i)
      stepping = { sh = sh, dir = dir, list = from, index = i }
      break
    end
  end
  history(dir)
  if stepping then
    rift.exec_action("editor:run:lua _rift_commands.IndentHistoryStep.fn({})")
  end
end

function M.history_step()
  local st = stepping
  stepping = nil
  if not st then return end
  if rift.current_buf() ~= st.sh.buf or buffer_text() ~= st.sh.mid then
    -- Something else that happened to leave the same text: that was its
    -- undo. The shift is still further back, so keep it.
    table.insert(st.list, math.min(st.index, #st.list + 1), st.sh)
    return
  end
  history(st.dir)
  place_cursor(st.sh.s, st.sh.ucol)
  local to = st.dir == "undo" and unshifts or shifts
  to[#to + 1] = st.sh
end

function M.undo() step("undo") end
function M.redo() step("redo") end

-- `>` / `<`: in Visual, shift at once (Neovim's `>gv`); in Normal, a second
-- `>` / `<` on the same spot shifts the line (`>>` / `<<`). Mapping `>>`
-- instead would make a lone Visual `>` wait for rift's key timeout.
local pending -- { buf, row, col, dir }

function M.key(dir)
  if rift.get_mode() == "visual" then
    pending = nil
    return M.shift_visual(dir)
  end
  local buf, row, col = rift.current_buf(), cursor()
  if pending and pending.dir == dir and pending.buf == buf
    and pending.row == row and pending.col == col then
    pending = nil
    return M.shift_current(dir, 1)
  end
  pending = { buf = buf, row = row, col = col, dir = dir }
end

function M.shift_current(dir, count)
  local row = cursor()
  M.shift_range(dir, row, row + math.max(1, count or 1) - 1)
end

-- Shifts the live Visual selection and any banked regions. Charwise and
-- linewise regions shift whole lines, each line once; blockwise regions shift
-- the text from the block's left edge, like Neovim.
function M.shift_selection(dir)
  if not editable() then return end
  if legacy then
    rift.notify("warn", "Indent: this rift build has no rift.get_selection()")
    return
  end
  local regions = rift.get_selection()
  if #regions == 0 then
    rift.notify("warn", "Indent: nothing selected")
    return
  end
  local sw, ts, expand = shiftwidth(), rift.get_tab_width(), rift.get_expand_tabs()
  local cur_row, cur_col = rift.get_cursor()

  local main = regions[1]
  for _, r in ipairs(regions) do
    if r.active then main = r break end
  end

  -- Work out every new line before editing: replace_lines is queued, so
  -- get_lines keeps returning the old text until the command returns.
  local new, block_left = {}, {}
  local selected = {}
  for _, r in ipairs(regions) do
    if r.kind == "block" then
      local top, bottom = line_at(r.start_row), line_at(r.end_row)
      local left = math.min((vcol_at(chars_of(top), r.start_col, ts)),
        (vcol_at(chars_of(bottom), r.end_col, ts)))
      block_left[r] = left
      for row = r.start_row, r.end_row do
        new[row] = shift_block_line(new[row] or line_at(row), dir, left, sw, ts, expand)
      end
    else
      for row = r.start_row, r.end_row do selected[row] = true end
    end
  end
  for row in pairs(selected) do
    new[row] = shift_line(new[row] or line_at(row), dir, sw, ts, expand)
  end

  -- Cursor, from the selection Neovim would have: a block puts it at its
  -- top-left corner, otherwise it goes to the first line at the cursor's
  -- screen column.
  local target_row, target_col
  if main.kind == "block" then
    target_row = main.start_row
    target_col = coladvance(line_at(target_row), block_left[main], ts)
  else
    local at_start = cur_row == main.start_row and cur_col == main.start_col
    local want = cursor_vcol(line_at(cur_row), cur_col, ts, at_start)
    target_row = main.start_row
    target_col = coladvance(new[target_row] or line_at(target_row), want, ts)
  end
  local final = new[target_row] or line_at(target_row)
  target_col = math.min(target_col, math.max(0, (utf8.len(final) or #final) - 1))

  -- Leave Visual and drop the banked regions before editing: the first
  -- mode:normal banks the live selection, the second clears the bank.
  rift.exec_action("mode:normal")
  rift.exec_action("mode:normal")
  -- Undo restores the cursor from before the edit, so move it first: `u`
  -- then lands on the first shifted line, as in Neovim.
  rift.set_cursor(target_row, target_col)

  -- One replace per contiguous run of changed rows. Line counts don't
  -- change, so the order doesn't matter.
  local rows = {}
  for row in pairs(new) do rows[#rows + 1] = row end
  table.sort(rows)
  local i = 1
  while i <= #rows do
    local s, e = rows[i], rows[i]
    while rows[i + 1] == e + 1 do
      i = i + 1
      e = rows[i]
    end
    local run = {}
    for row = s, e do run[#run + 1] = new[row] end
    replace(s, e, run)
    i = i + 1
  end

  if not (opts.reselect and main.active) then
    rift.set_cursor(target_row, target_col)
    return
  end

  -- Select the same rows and columns again, like Neovim's `>gv`: the anchor
  -- is whichever end of the selection the cursor isn't on.
  local anchor_row, anchor_col = main.start_row, main.start_col
  if cur_row == main.start_row and cur_col == main.start_col then
    anchor_row, anchor_col = main.end_row, main.end_col
  end
  -- A column past a now-shorter line lands on its end, which Visual mode
  -- (unlike Normal) can select.
  local function clamped(row, col)
    local line = new[row] or line_at(row)
    return row, math.min(col, utf8.len(line) or #line)
  end
  rift.set_cursor(clamped(anchor_row, anchor_col))
  rift.exec_action(({ char = "mode:visual", line = "mode:visual_line",
    block = "mode:visual_block" })[main.kind])
  rift.set_cursor(clamped(cur_row, cur_col))
end

local function count_arg(args)
  return tonumber(args[1] or "") or 1
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end


  rift.on("ModeChanged", function(ev)
    pending = nil
    local to, from = ev.to or "", ev.from or ""
    local to_visual, from_visual = to:find("^visual") ~= nil, from:find("^visual") ~= nil
    if to_visual and not from_visual then
      local row, col = rift.get_cursor()
      visual_start = { buf = rift.current_buf(), row = row, col = col, kind = to }
    elseif to_visual and visual_start then
      visual_start.kind = to -- v / V / <C-v> switch kind, same anchor
    elseif not to_visual then
      visual_start = nil
    end
  end)
  -- A pending `>` / `<` is dropped by anything else that happens.
  rift.on("CursorMoved", function() pending = nil end)
  rift.on("TextChangedCoarse", function() pending = nil end)

  rift.register_command("Indent", function(args)
    M.shift_current(1, count_arg(args))
  end, "Shift [count] lines one shiftwidth right")
  rift.register_command("Dedent", function(args)
    M.shift_current(-1, count_arg(args))
  end, "Shift [count] lines one shiftwidth left")
  rift.register_command("IndentSelection", function()
    M.shift_selection(1)
  end, "Shift the selection one shiftwidth right")
  rift.register_command("DedentSelection", function()
    M.shift_selection(-1)
  end, "Shift the selection one shiftwidth left")

  if not opts.mappings then return end

  -- A bare "<" opens a <...> key token, so it has to be written <lt>.
  rift.register_command("IndentKey", function() M.key(1) end,
    "`>`: shift the Visual selection, or the line on a second `>`")
  rift.register_command("DedentKey", function() M.key(-1) end,
    "`<`: shift the Visual selection, or the line on a second `<`")
  rift.register_command("IndentUndo", function() M.undo() end,
    "Undo, taking a Visual shift in one step")
  rift.register_command("IndentRedo", function() M.redo() end,
    "Redo, taking a Visual shift in one step")
  rift.register_command("IndentHistoryStep", function() M.history_step() end,
    "Internal: second step of undoing / redoing a Visual shift")
  -- Visual mode falls back to Normal-mode keys, so these work in both.
  map("n", ">", "IndentKey")
  map("n", "<lt>", "DedentKey")
  -- Mapped once every plugin is loaded, so this wins over other `u` maps
  -- (rift-clipboard's is called from here).
  rift.on("EditorStart", function()
    map("n", "u", "IndentUndo")
    map("n", "<C-r>", "IndentRedo")
  end)
end

M._shift_line = shift_line
M._shift_block_line = shift_block_line

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
