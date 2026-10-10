-- Neovim-style `>>` / `<<` line shifting, plus `>` / `<` in visual mode.
local M = {}

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
  if v < left then return line end
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

-- rift 0.7.1 (the crates.io release) predates `rift.get_selection` and has
-- four bugs this plugin has to steer around there:
--   * replace_lines drops the newline after the range, joining the next line
--     onto the last replaced one;
--   * replace_lines is two undo steps, so `u` first deletes the line;
--   * the snapshot plugins read is only refreshed when the text changes, so
--     after `j` rift.get_cursor() still reports the last edited line;
--   * plugin commands run before that refresh, so a fast `>>>>` sees the line
--     from before the first shift.
-- On those builds only the indent is edited, with insert/delete at the start
-- of the line inside one Insert-mode undo group; the cursor comes from
-- CursorMoved events; and the plugin remembers what it just wrote until the
-- snapshot catches up.
local legacy = rift.get_selection == nil

-- Lines this plugin edited since the last snapshot, by row: { before, after }.
local written = {}
local written_buf

-- The cursor as of the last CursorMoved event or shift, when newer than the
-- snapshot: { buf, row, col }.
local moved

local function cursor()
  if legacy and moved and moved.buf == rift.current_buf() then
    return moved.row, moved.col
  end
  return rift.get_cursor()
end

local function place_cursor(row, col)
  rift.set_cursor(row, col)
  if legacy then moved = { buf = rift.current_buf(), row = row, col = col } end
end

local function line_at(row)
  local line = rift.get_lines(row, row)[1] or ""
  local w = written[row]
  if legacy and w and written_buf == rift.current_buf() and line == w.before then
    return w.after
  end
  return line
end

local function lines_in(s, e)
  local out = {}
  for row = s, e do out[#out + 1] = line_at(row) end
  return out
end

-- Rewrites line `row` from `old` to `new` by touching only the indent that
-- differs. An insert is a single undo step on every rift build.
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
  if written_buf ~= rift.current_buf() then
    written, written_buf = {}, rift.current_buf()
  end
  -- Keep the text the snapshot still shows, however many shifts ago it was.
  local prev = written[row]
  local before = (prev and prev.after == old) and prev.before or old
  written[row] = { before = before, after = new }
end

local function replace(s, e, lines)
  if not legacy then
    rift.replace_lines(s, e, lines)
    return
  end
  -- Each delete is its own undo step on these builds; Insert mode groups
  -- everything until it is left into one, so `u` undoes the whole shift.
  rift.exec_action("mode:insert")
  for i, new in ipairs(lines) do
    local row = s + i - 1
    local old = line_at(row)
    if old ~= new then edit_indent(row, old, new) end
  end
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
  place_cursor(s, coladvance(new[1], want, ts))
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

  if legacy then
    -- Both fire once per render, right after the buffer snapshot refreshes.
    -- TextChangedCoarse fires once per render, right after the snapshot is
    -- refreshed; CursorMoved fires then too but refreshes nothing.
    rift.on("TextChangedCoarse", function()
      written, moved = {}, nil
    end)
    rift.on("CursorMoved", function(ev)
      moved = { buf = ev.buf, row = ev.row, col = ev.col }
    end)
  end

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
  rift.map("n", ">>", "editor:run:Indent")
  rift.map("n", "<lt><lt>", "editor:run:Dedent")
  rift.map("v", ">", "editor:run:IndentSelection")
  rift.map("v", "<lt>", "editor:run:DedentSelection")
end

M._shift_line = shift_line
M._shift_block_line = shift_block_line

return M
