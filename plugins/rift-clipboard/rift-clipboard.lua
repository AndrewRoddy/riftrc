-- Yanks go to the system clipboard, like Neovim's clipboard=unnamedplus.
--
-- rift never writes the system clipboard, and plugins can't see its yanks or
-- run its yank operator. So Normal-mode `y` is taken over here: `yy`, `yiw`,
-- `y$`, ... are mapped to Lua that copies the text to the clipboard
-- (clip.exe on Windows) and keeps it in a register of our own.
--
-- Why `y` itself is mapped: rift runs an operator key immediately when it's
-- also the start of longer mappings, so a mapping like `yy` never fires
-- while `y` is still the operator. Mapping `y` replaces the operator in
-- Normal mode (Visual mode has its own keys and keeps rift's `y`). The
-- price is that a `y{motion}` not listed in YANKS below does nothing.
--
-- Our yanks never reach rift's register, so `p`/`P` paste ours while it is
-- the newest thing yanked. Once rift may have something newer -- Visual mode
-- was used, or text was deleted in Normal mode (dd, x, d{motion}) -- `p`/`P`
-- go back to rift's own. `u`/<C-r> are mapped so undoing a paste doesn't
-- count as a delete.
--
-- Visual-mode `y` is copied too: see "Visual-mode yanks" below.
--
-- Not covered: counts (3yy, 2yw), dot-repeat and deletes.
local M = {}
local MODULE = ...

-- Helpers -------------------------------------------------------------------

local is_windows = package.config:sub(1, 1) == "\\"
local sep = is_windows and "\\" or "/"

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

local function write_file(path, text)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(text)
  f:close()
  return true
end

local function split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  return lines
end

-- Finds an executable on PATH (trying .exe/.cmd/.bat on Windows).
local function which(name)
  for dir in (os.getenv("PATH") or ""):gmatch(is_windows and "[^;]+" or "[^:]+") do
    for _, ext in ipairs(is_windows and { ".exe", ".cmd", ".bat", "" } or { "" }) do
      if file_exists(dir .. sep .. name .. ext) then return dir .. sep .. name .. ext end
    end
  end
end

-- rift.replace_lines drops the newline after the range, joining the next
-- line onto the last new one, and takes two undo steps. This puts the
-- newline back and, from Normal mode, wraps the edit in a brief Insert mode
-- so `u` undoes it in one step.
local function set_lines(s, e, lines)
  local out = { table.unpack(lines) }
  if #out > 0 and e < rift.get_line_count() then out[#out + 1] = "" end
  local wrap = rift.get_mode() == "normal"
  if wrap then rift.exec_action("mode:insert") end
  rift.replace_lines(s, e, out)
  if wrap then rift.exec_action("mode:normal") end
end

-- Length in characters (rift's columns count characters, not bytes).
local function char_len(s) return utf8.len(s) or #s end

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
  -- Show "N lines yanked" for yanks longer than this many lines (Neovim's 'report').
  report = 2,
  -- Copy Visual-mode yanks too (see "Visual-mode yanks" below).
  visual = true,
  -- The CursorHold delay put back after checking a Visual-mode yank.
  -- rift's default is 400 ms; set this if your config changes it.
  cursor_hold_ms = 400,
}

-- Our register: { text = string, linewise = bool }.
M.register = nil

---------------------------------------------------------------------------
-- Writing the system clipboard
---------------------------------------------------------------------------

local seq = 0

-- clip.exe reads UTF-16LE. Not with a BOM: it keeps the BOM as a character.
-- UTF-8 would come out in the OEM code page.
local function utf16le(s)
  local out = {}
  local ok = pcall(function()
    for _, cp in utf8.codes(s) do
      if cp >= 0x10000 then
        cp = cp - 0x10000
        local hi, lo = 0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)
        out[#out + 1] = string.char(hi & 0xFF, hi >> 8, lo & 0xFF, lo >> 8)
      else
        out[#out + 1] = string.char(cp & 0xFF, cp >> 8)
      end
    end
  end)
  if not ok then -- not valid UTF-8: treat each byte as Latin-1
    out = {}
    for i = 1, #s do out[#out + 1] = string.char(s:byte(i), 0) end
  end
  return table.concat(out)
end

-- Program and args that put the contents of the file at `path` on the
-- system clipboard. Replaced in tests.
function M.copy_command(path)
  if is_windows then
    if not path:find(" ", 1, true) then
      -- rift.spawn quotes this argument; cmd removes the quotes again
      -- because the command contains `<`.
      return "cmd", { "/C", "clip < " .. path }
    end
    return "powershell", { "-NoProfile", "-NonInteractive", "-Command",
      "Set-Clipboard -Value ([IO.File]::ReadAllText('" .. path:gsub("'", "''") .. "'))" }
  end
  local tool = which("pbcopy") and "pbcopy"
    or which("wl-copy") and "wl-copy"
    or "xclip -selection clipboard"
  return "sh", { "-c", tool .. ' < "$1"', "sh", path }
end

local function uses_clip(path)
  return is_windows and not path:find(" ", 1, true)
end

-- One file, rewritten for every copy, so nothing piles up in %TEMP% when
-- rift exits before a copy finishes.
local copy_path = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. sep
  .. "rift-clipboard.txt"

function M.copy_to_system(text)
  local path = copy_path
  local data = uses_clip(path) and utf16le((text:gsub("\r?\n", "\r\n"))) or text
  local ok, err = write_file(path, data)
  if not ok then
    rift.notify("error", "clipboard: can't write temp file: " .. tostring(err))
    return
  end
  local prog, args = M.copy_command(path)
  seq = seq + 1
  rift.spawn(prog, args, "rift-clipboard:" .. seq)
end

---------------------------------------------------------------------------
-- Text helpers (columns are characters, 1-indexed inside this file)
---------------------------------------------------------------------------

local function chars_of(line)
  local t = {}
  for _, c in utf8.codes(line) do t[#t + 1] = utf8.char(c) end
  return t
end

-- 1 = keyword character, 2 = other non-blank, 0 = blank. With `big`, every
-- non-blank is 1 (WORDs).
local function class(c, big)
  if not c or c:match("^%s$") then return 0 end
  if big then return 1 end
  return (c:match("^[%w_]$") or #c > 1) and 1 or 2
end

local function buffer_lines()
  local lines = rift.get_lines(1, -1)
  -- rift counts the empty line after a final newline; drop it.
  if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

---------------------------------------------------------------------------
-- Motions and text objects -> regions
--
-- A region is { sr, sc, er, ec, linewise } with rows 1-indexed and columns
-- 1-indexed character positions, end inclusive. Linewise regions ignore the
-- columns. `cursor` is where the cursor goes afterwards, { row, col1 }.
---------------------------------------------------------------------------

local function word_object(t, pos, around, big)
  if #t == 0 then return nil end
  pos = math.min(pos, #t)
  local cls = class(t[pos], big)
  local s, e = pos, pos
  while s > 1 and class(t[s - 1], big) == cls do s = s - 1 end
  while e < #t and class(t[e + 1], big) == cls do e = e + 1 end
  if not around then return s, e end
  if cls == 0 then
    if e < #t then
      local c2 = class(t[e + 1], big)
      while e < #t and class(t[e + 1], big) == c2 do e = e + 1 end
    end
  elseif e < #t and class(t[e + 1], big) == 0 then
    while e < #t and class(t[e + 1], big) == 0 do e = e + 1 end
  else
    while s > 1 and class(t[s - 1], big) == 0 do s = s - 1 end
  end
  return s, e
end

-- Last position covered by `w`/`W` from pos, on this line.
local function w_end(t, pos, big)
  local cls = class(t[pos], big)
  local e = pos
  if cls ~= 0 then
    while e < #t and class(t[e + 1], big) == cls do e = e + 1 end
  end
  while e < #t and class(t[e + 1], big) == 0 do e = e + 1 end
  return e
end

-- `e`/`E` from pos: end of the current word, or of the next one if already there.
local function e_end(t, pos, big)
  local e = pos
  if e < #t and class(t[e + 1], big) == class(t[e], big) and class(t[e], big) ~= 0 then
    while e < #t and class(t[e + 1], big) == class(t[pos], big) do e = e + 1 end
    return e
  end
  e = e + 1
  while e < #t and class(t[e], big) == 0 do e = e + 1 end
  if e > #t then return #t end
  local cls = class(t[e], big)
  while e < #t and class(t[e + 1], big) == cls do e = e + 1 end
  return e
end

-- `b`/`B` from pos: start of the current word, or of the previous one.
local function b_start(t, pos, big)
  local s = pos - 1
  while s >= 1 and class(t[s], big) == 0 do s = s - 1 end
  if s < 1 then return 1 end
  local cls = class(t[s], big)
  while s > 1 and class(t[s - 1], big) == cls do s = s - 1 end
  return s
end

local function paragraph(lines, row, around)
  local total = #lines
  local blank = function(i) return not (lines[i] or ""):match("%S") end
  local s, e = row, row
  local kind = blank(row)
  while s > 1 and blank(s - 1) == kind do s = s - 1 end
  while e < total and blank(e + 1) == kind do e = e + 1 end
  if around then
    if e < total then
      local k2 = blank(e + 1)
      while e < total and blank(e + 1) == k2 do e = e + 1 end
    else
      while s > 1 and blank(s - 1) do s = s - 1 end
    end
  end
  return s, e
end

-- Quotes on the cursor line: the pair around the cursor, else the first
-- pair after it.
local function quote_object(t, pos, q, around)
  local qs = {}
  for i, c in ipairs(t) do
    if c == q and t[i - 1] ~= "\\" then qs[#qs + 1] = i end
  end
  local s, e
  for k = 1, #qs - 1, 2 do
    if qs[k] <= pos and pos <= qs[k + 1] then s, e = qs[k], qs[k + 1] break end
  end
  if not s then
    for k = 1, #qs - 1 do
      if qs[k] > pos then s, e = qs[k], qs[k + 1] break end
    end
  end
  if not s then return nil end
  if not around then return s + 1, e - 1 end
  local e2 = e
  while e2 < #t and class(t[e2 + 1]) == 0 do e2 = e2 + 1 end
  return s, e2
end

local PAIRS = { ["("] = ")", ["["] = "]", ["{"] = "}", ["<"] = ">" }

-- Brackets around the cursor, across lines. Returns sr, sc, er, ec of the
-- open and close brackets themselves.
local function bracket_object(lines, row, pos, open)
  local close = PAIRS[open]
  local rows = {}
  local function ch(r, c)
    rows[r] = rows[r] or chars_of(lines[r] or "")
    return rows[r][c]
  end
  local function len(r) ch(r, 1); return #rows[r] end
  -- Backwards for the unmatched open (the cursor may be on it).
  local r, c, depth = row, pos, 0
  -- On the closing bracket: its own pair, so start just before it.
  if ch(r, c) == close then c = c - 1 end
  local sr, sc
  while r >= 1 do
    while c >= 1 do
      local x = ch(r, c)
      if x == close then depth = depth + 1
      elseif x == open then
        if depth == 0 then sr, sc = r, c break end
        depth = depth - 1
      end
      c = c - 1
    end
    if sr then break end
    r = r - 1
    if r >= 1 then c = len(r) end
  end
  if not sr then return nil end
  -- Forwards from just after it for the match.
  r, c, depth = sr, sc + 1, 0
  while r <= #lines do
    while c <= len(r) do
      local x = ch(r, c)
      if x == open then depth = depth + 1
      elseif x == close then
        if depth == 0 then return sr, sc, r, c end
        depth = depth - 1
      end
      c = c + 1
    end
    r, c = r + 1, 1
  end
  return nil
end

-- Positions just inside (sr,sc)..(er,ec), stepping over line ends.
local function shrink(lines, sr, sc, er, ec)
  local nsr, nsc = sr, sc + 1
  if nsc > char_len(lines[sr]) then nsr, nsc = sr + 1, 1 end
  local ner, nec = er, ec - 1
  if nec < 1 then ner = er - 1; nec = char_len(lines[ner] or "") end
  return nsr, nsc, ner, nec
end

-- Builds the region for a motion name (see YANKS). Returns region, cursor.
local function region_for(what, arg)
  local lines = buffer_lines()
  local row, col0 = rift.get_cursor()
  local line = lines[row] or ""
  local t = chars_of(line)
  local pos = math.min(col0 + 1, math.max(#t, 1))

  local function charwise(s, e) -- on the cursor line
    if not s or s > e or e < 1 or #t == 0 then return nil end
    return { sr = row, sc = s, er = row, ec = e }, { row, s }
  end
  local function linewise(s, e, cursor_row)
    return { sr = s, er = e, linewise = true }, { cursor_row or s, nil }
  end

  if what == "line" then return linewise(row, row, row) end
  if what == "down" then return linewise(row, math.min(row + 1, #lines), row) end
  if what == "up" then return linewise(math.max(row - 1, 1), row) end
  if what == "gg" then return linewise(1, row) end
  if what == "G" then return linewise(row, #lines, row) end
  if what == "para_next" then
    local e = row
    while e < #lines and lines[e + 1]:match("%S") do e = e + 1 end
    return linewise(row, e, row)
  end
  if what == "para_prev" then
    -- `y{` from inside a paragraph: back to (and including) the blank line
    -- before it, up to the line above the cursor -- linewise, like Vim
    -- when the cursor is at the start of its line.
    local s = row - 1
    while s > 1 and lines[s]:match("%S") do s = s - 1 end
    if s < 1 or row - 1 < s then return nil end
    return linewise(s, row - 1)
  end
  if what == "l" then return charwise(pos, pos) end
  if what == "h" then return charwise(pos - 1, pos - 1) end
  if what == "%" then
    -- The first bracket at or after the cursor on this line, to its match.
    for i = pos, #t do
      local c = t[i]
      local open = PAIRS[c] and c or nil
      if not open then
        for o, cl in pairs(PAIRS) do if cl == c and o ~= "<" then open = o end end
      end
      if open and open ~= "<" then
        local sr, sc, er, ec = bracket_object(lines, row, i, open)
        if not sr then return nil end
        return { sr = sr, sc = sc, er = er, ec = ec }, { sr, sc }
      end
    end
    return nil
  end
  if what == "eol" then return charwise(pos, #t) end
  if what == "bol" then return charwise(1, pos - 1) end
  if what == "bol_nonblank" then
    local fnb = (line:find("%S") and char_len(line:match("^%s*")) + 1) or 1
    if fnb < pos then return charwise(fnb, pos - 1) end
    return charwise(pos, fnb - 1)
  end
  if what == "w" or what == "W" then return charwise(pos, w_end(t, pos, what == "W")) end
  if what == "e" or what == "E" then return charwise(pos, e_end(t, pos, what == "E")) end
  if what == "b" or what == "B" then return charwise(b_start(t, pos, what == "B"), pos - 1) end
  if what == "f" or what == "t" then
    for i = pos + 1, #t do
      if t[i] == arg then return charwise(pos, what == "f" and i or i - 1) end
    end
    return nil
  end
  if what == "F" or what == "T" then
    for i = pos - 1, 1, -1 do
      if t[i] == arg then return charwise(what == "F" and i or i + 1, pos - 1) end
    end
    return nil
  end
  local around = what:sub(1, 1) == "a"
  local obj = what:sub(2)
  if obj == "w" or obj == "W" then return charwise(word_object(t, pos, around, obj == "W")) end
  if obj == "p" then return linewise(paragraph(lines, row, around)) end
  if obj == '"' or obj == "'" or obj == "`" then return charwise(quote_object(t, pos, obj, around)) end
  if PAIRS[obj] then
    local sr, sc, er, ec = bracket_object(lines, row, pos, obj)
    if not sr then return nil end
    if not around then
      sr, sc, er, ec = shrink(lines, sr, sc, er, ec)
      if er < sr or (er == sr and ec < sc) then return nil end
    end
    return { sr = sr, sc = sc, er = er, ec = ec }, { sr, sc }
  end
  return nil
end

local function region_text(r)
  local lines = buffer_lines()
  if r.linewise then
    return table.concat(lines, "\n", r.sr, r.er), r.er - r.sr + 1
  end
  local out = {}
  for row = r.sr, r.er do
    local t = chars_of(lines[row] or "")
    local s = row == r.sr and r.sc or 1
    local e = row == r.er and r.ec or #t
    out[#out + 1] = table.concat(t, "", s, math.min(e, #t))
  end
  return table.concat(out, "\n"), #out
end

---------------------------------------------------------------------------
-- p / P switching
---------------------------------------------------------------------------

local put_mapped = false
local last_size -- buffer size (bytes) as of our last yank/put

local function buffer_size()
  local n = 0
  for _, l in ipairs(rift.get_lines(1, -1)) do n = n + #l + 1 end
  return n
end

local function use_ours()
  last_size = buffer_size()
  if put_mapped then return end
  put_mapped = true
  map("n", "p", "ClipboardPut after")
  map("n", "P", "ClipboardPut before")
end

local function use_rifts()
  if not put_mapped then return end
  put_mapped = false
  -- unmap pops our layer, which brings rift's own p/P back.
  rift.unmap("n", "p")
  rift.unmap("n", "P")
end

---------------------------------------------------------------------------
-- Visual-mode yanks
--
-- rift's Visual `y` is its own, and plugins can't map Visual-mode keys or
-- see the selection. What they can see: where Visual mode started
-- (ModeChanged, normal -> visual*), where the cursor was when it ended
-- (ModeChanged, visual* -> normal), and -- a moment later -- where the
-- cursor ended up. `y` moves the cursor to the start of the selection;
-- `Esc` leaves it where it was.
--
-- "A moment later" takes some doing. ModeChanged fires before `y` moves
-- the cursor, and that move fires no event. While rift is idle the only
-- thing that runs plugin code is CursorHold, which fires once per idle
-- period and is re-armed only by a CursorMoved to a new position. So when
-- Visual mode ends:
--   * the CursorHold delay is set to one poll (and put back afterwards);
--   * if no CursorMoved came since the last CursorHold, the cursor is
--     nudged one step with a motion, which queues a CursorMoved. rift
--     applies the nudge before `y` sets the cursor, so a yank still ends at
--     the start; after `Esc` the nudge is undone once the check has run.
--
-- When the cursor was already at the selection's start (a backwards
-- selection, or `vy`), `y` and `Esc` look the same; that counts as a yank
-- and is decided straight away.
---------------------------------------------------------------------------

local visual -- { kind, anchor = { row, col }, size, buf } while in Visual mode
local pending -- the Visual selection just left, until CursorHold decides
local hold_armed = false -- a CursorMoved has come since the last CursorHold

local function set_hold_delay(ms)
  if rift.set_cursor_hold_delay then rift.set_cursor_hold_delay(ms) end
end

local function before(ar, ac, br, bc)
  return ar < br or (ar == br and ac <= bc)
end

-- The region (as region_text wants it) and where `y` leaves the cursor.
local function visual_region(p)
  local ar, ac, er, ec = p.anchor[1], p.anchor[2], p.cursor[1], p.cursor[2]
  if p.kind == "visualline" then
    return { sr = math.min(ar, er), er = math.max(ar, er), linewise = true },
      math.min(ar, er), 0
  end
  if p.kind == "visualblock" then
    local sc, ecol = math.min(ac, ec), math.max(ac, ec)
    return { sr = math.min(ar, er), er = math.max(ar, er), block = { sc + 1, ecol + 1 } },
      math.min(ar, er), sc
  end
  if not before(ar, ac, er, ec) then ar, ac, er, ec = er, ec, ar, ac end
  return { sr = ar, sc = ac + 1, er = er, ec = ec + 1 }, ar, ac
end

local function block_text(r)
  local lines = buffer_lines()
  local out = {}
  for row = r.sr, r.er do
    local t = chars_of(lines[row] or "")
    out[#out + 1] = table.concat(t, "", r.block[1], math.min(r.block[2], #t))
  end
  return table.concat(out, "\n"), #out
end

local function copy_visual(p, region)
  local text, nlines
  if region.block then text, nlines = block_text(region) else text, nlines = region_text(region) end
  M.copy_to_system(region.linewise and (text .. "\n") or text)
  if nlines > opts.report then rift.notify("info", nlines .. " lines yanked") end
end

-- Moves the cursor one step from p.cursor, anywhere but onto the
-- selection's start (sr, sc). Returns where it went ({ row, col or nil }).
local function nudge(p, sr, sc)
  local lines = buffer_lines()
  local r, c = p.cursor[1], p.cursor[2]
  local len = char_len(lines[r] or "")
  local moves = {}
  if c + 1 < len then moves[#moves + 1] = { "editor:move:right", r, c + 1 } end
  if r < #lines then moves[#moves + 1] = { "editor:move:down", r + 1 } end
  if c > 0 then moves[#moves + 1] = { "editor:move:left", r, c - 1 } end
  if r > 1 then moves[#moves + 1] = { "editor:move:up", r - 1 } end
  for _, m in ipairs(moves) do
    local onto_start = m[2] == sr and (m[3] == nil or m[3] == sc)
    if not onto_start then
      rift.exec_action(m[1])
      return { m[2], m[3] }
    end
  end
end

local function decide_visual()
  local p = pending
  pending = nil
  set_hold_delay(opts.cursor_hold_ms)
  if not p or rift.current_buf() ~= p.buf then return end
  -- d, c, x, ... in Visual mode changed the text: a delete, not a yank.
  if buffer_size() ~= p.size then return end
  local region, sr, sc = visual_region(p)
  local row, col = rift.get_cursor()
  if row == sr and col == sc then
    copy_visual(p, region)
  elseif p.nudged and row == p.nudged[1] and (p.nudged[2] == nil or col == p.nudged[2]) then
    rift.set_cursor(p.cursor[1], p.cursor[2]) -- Esc: undo the nudge
  end
end

local function on_visual_mode(ev)
  if not opts.visual then return end
  local kind = rift.buf_kind()
  if ev.to:find("^visual") then
    if not ev.from:find("^visual") then
      local r, c = rift.get_cursor()
      visual = { anchor = { r, c }, size = buffer_size(), buf = rift.current_buf() }
      pending = nil
    end
    if visual then visual.kind = ev.to end
  elseif ev.from:find("^visual") and visual then
    local v = visual
    visual = nil
    if ev.to ~= "normal" or (kind ~= "file" and kind ~= "scratch") then return end
    local r, c = rift.get_cursor()
    local p = { kind = v.kind, anchor = v.anchor, cursor = { r, c }, size = v.size, buf = v.buf }
    local region, sr, sc = visual_region(p)
    if r == sr and c == sc then
      -- y and Esc would look the same: count it as a yank, no need to wait.
      if buffer_size() == p.size then copy_visual(p, region) end
      return
    end
    pending = p
    set_hold_delay(1)
    if not hold_armed then p.nudged = nudge(p, sr, sc) end
  end
end

---------------------------------------------------------------------------
-- Yank / put
---------------------------------------------------------------------------

function M.yank(what, arg)
  local kind = rift.buf_kind()
  if kind ~= "file" and kind ~= "scratch" then return end
  local region, cursor = region_for(what, arg)
  if not region then return end
  local text, nlines = region_text(region)
  M.register = { text = text, linewise = region.linewise == true }
  M.copy_to_system(region.linewise and (text .. "\n") or text)
  use_ours()
  if cursor[1] then
    local row = cursor[1]
    local col = cursor[2] and cursor[2] - 1 or select(2, rift.get_cursor())
    if cursor[2] or row ~= (rift.get_cursor()) then rift.set_cursor(row, col) end
  end
  if nlines > opts.report then
    rift.notify("info", nlines .. " lines yanked")
  end
end

local function first_nonblank(s)
  return char_len(s:match("^%s*"))
end

function M.put(before)
  local reg = M.register
  if not reg then return end
  local row, col = rift.get_cursor()
  local line = rift.get_lines(row, row)[1] or ""
  -- Plugin edits don't fire TextChangedCoarse, so account for this one here.
  if last_size then last_size = last_size + #reg.text + (reg.linewise and 1 or 0) end
  M._undoing = false
  M._own_insert = rift.get_mode() == "normal" -- set_lines switches to Insert and back

  local new = split_lines(reg.text)
  if reg.linewise then
    local repl = {}
    if not before then repl[1] = line end
    for _, l in ipairs(new) do repl[#repl + 1] = l end
    if before then repl[#repl + 1] = line end
    set_lines(row, row, repl)
    rift.set_cursor(before and row or row + 1, first_nonblank(new[1]))
    return
  end

  local t = chars_of(line)
  local at = before and col or math.min(col + 1, #t) -- characters kept before the text
  local head, tail = table.concat(t, "", 1, at), table.concat(t, "", at + 1, #t)
  local last = #new
  -- Cursor ends on the last pasted character, like Neovim.
  local cursor_col = (last == 1 and at or 0) + char_len(new[last]) - 1
  new[1] = head .. new[1]
  new[last] = new[last] .. tail
  set_lines(row, row, new)
  rift.set_cursor(row + last - 1, math.max(0, cursor_col))
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- Key sequence after `y` -> motion name passed to M.yank.
local YANKS = {
  y = "line", ["$"] = "eol", ["0"] = "bol", ["^"] = "bol_nonblank",
  w = "w", W = "W", e = "e", E = "E", b = "b", B = "B",
  j = "down", k = "up", gg = "gg", G = "G", ["}"] = "para_next",
  ["{"] = "para_prev", l = "l", h = "h", ["_"] = "line", ["%"] = "%",
}
for _, ia in ipairs({ "i", "a" }) do
  for _, obj in ipairs({ "w", "W", "p", '"', "'", "`" }) do YANKS[ia .. obj] = ia .. obj end
  for open, close in pairs(PAIRS) do
    YANKS[ia .. open] = ia .. open
    YANKS[ia .. close] = ia .. open
  end
  YANKS[ia .. "b"] = ia .. "("
  YANKS[ia .. "B"] = ia .. "{"
end

-- rift key notation for a literal character.
local function key(c)
  if c == "<" then return "<lt>" end
  if c == " " then return "<Space>" end
  return c
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end

  rift.register_command("ClipboardYank", function(args) M.yank(args[1] or "line", args[2]) end,
    "Yank to the system clipboard (motion name, e.g. line, iw, eol)")
  rift.register_command("ClipboardPut", function(args) M.put(args[1] == "before") end,
    "Paste the last clipboard yank: after | before")
  rift.register_command("ClipboardUndo", function(args)
    M._undoing = true
    rift.exec_action(args[1] == "redo" and "history:redo" or "history:undo")
  end, "Undo/redo without making p fall back to rift's register")
  rift.register_command("ClipboardNoop", function() end, "Unsupported y{motion}")

  -- `y` alone (timed out, or followed by an unsupported motion) does nothing.
  map("n", "y", "ClipboardNoop")
  map("n", "Y", "ClipboardYank eol")
  for seq, what in pairs(YANKS) do
    local keys = seq:gsub(".", key)
    map("n", "y" .. keys, "ClipboardYank " .. what)
  end
  -- yf{char} yt{char} yF{char} yT{char} for printable ASCII.
  for b = 33, 126 do
    local c = string.char(b)
    for _, m in ipairs({ "f", "t", "F", "T" }) do
      map("n", "y" .. m .. key(c), "ClipboardYank " .. m .. " " .. c)
    end
  end
  map("n", "u", "ClipboardUndo")
  map("n", "<C-r>", "ClipboardUndo redo")

  if M._registered then return end
  M._registered = true

  rift.on("UserEvent", function(ev)
    if ev.name ~= "ShellDone" or not tostring(ev.tag):find("^rift%-clipboard:") then return end
    if not ev.success then
      rift.notify("error", "clipboard: copy failed: " .. (ev.output or ""))
    end
  end)

  -- Signs that rift's register may now hold something newer than ours:
  --   * Visual mode (it may have yanked);
  --   * operator-pending mode: `y` is ours, so this is d, c, ... (dd and
  --     d{motion} fire no TextChangedCoarse, so this is the only sign);
  --   * entering Insert with less text than before: C, s, S deleted first.
  rift.on("ModeChanged", function(ev)
    if M._own_insert then
      -- M.put's own brief Insert mode (set_lines).
      if ev.to == "normal" then M._own_insert = false end
      return
    end
    on_visual_mode(ev)
    if ev.to:find("visual") or ev.to == "operatorpending" then
      use_rifts()
    elseif ev.from == "normal" and ev.to == "insert" and put_mapped
      and last_size and buffer_size() < last_size then
      use_rifts()
    end
  end)

  rift.on("CursorMoved", function() hold_armed = true end)
  rift.on("CursorHold", function()
    hold_armed = false
    if pending then decide_visual() end
  end)

  -- A Normal-mode change that removed text (x, X, D) was a delete, which
  -- went into rift's register. Undo/redo through `u`/<C-r> are excused.
  rift.on("TextChangedCoarse", function()
    if not put_mapped then return end
    local size = buffer_size()
    if M._undoing then
      M._undoing = false
    elseif rift.get_mode() == "normal" and size < last_size then
      use_rifts()
      return
    end
    last_size = size
  end)
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
