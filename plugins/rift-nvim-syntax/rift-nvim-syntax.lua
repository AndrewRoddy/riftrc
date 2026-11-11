-- Syntax highlighting exactly like Neovim's.
--
-- rift has its own tree-sitter highlighting, but its queries, its rules for
-- overlapping captures and its theme colors all differ from Neovim's. So
-- instead of imitating Neovim, this asks Neovim: a headless `nvim --clean`
-- parses the buffer with the same parsers and queries (nvim-treesitter,
-- injections, `#set! priority`, ...) and resolves every capture to the color
-- your Neovim config gives it (color, bold, italic, underline, ...). The
-- result is a list of byte ranges, drawn over rift's own highlighting as
-- annotations: one annotation kind per look, registered with its style.
--
-- The colors come from your real Neovim config: once per rift session a
-- headless `nvim` with your full config dumps every highlight group (and
-- the first run waits for it). Running the full config on every refresh
-- would be too slow; `nvim --clean` takes about 0.1 s plus the parse.
--
-- When it runs: on opening or entering a buffer, on CursorHold if the text
-- changed, and after an edit that leaves the cursor in place. rift's
-- plugins only get results from a background process when something else
-- happens (a key, CursorHold), and there's no timer, so the run is
-- synchronous: rift waits for it, about 0.1-0.2 s for a typical file.
-- Between runs, edited text keeps rift's own colors.
--
-- Not covered: LSP semantic tokens (Neovim colors some tokens from the
-- language server on top of tree-sitter), and highlights from other Neovim
-- plugins (e.g. color swatches).
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

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write_file(path, text)
  local f, err = io.open(path, "wb")
  if not f then return nil, err end
  f:write(text)
  f:close()
  return true
end

-- Finds an executable on PATH (trying .exe/.cmd/.bat on Windows).
local function which(name)
  for dir in (os.getenv("PATH") or ""):gmatch(is_windows and "[^;]+" or "[^:]+") do
    for _, ext in ipairs(is_windows and { ".exe", ".cmd", ".bat", "" } or { "" }) do
      if file_exists(dir .. sep .. name .. ext) then return dir .. sep .. name .. ext end
    end
  end
end

local function quote(s)
  if is_windows then return '"' .. s .. '"' end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Runs a command line and waits for it, discarding its output. (rift
-- disables os.execute; io.popen still works.)
local function run_sync(cmdline)
  local null = is_windows and "NUL" or "/dev/null"
  cmdline = cmdline .. " <" .. null .. " >" .. null .. " 2>&1"
  -- cmd /c strips the outer quotes when the line has several quoted parts.
  if is_windows then cmdline = '"' .. cmdline .. '"' end
  local p = io.popen(cmdline, "r")
  if not p then return false end
  p:read("a")
  return p:close()
end

-- Options -------------------------------------------------------------------

local opts = {
  -- The Neovim executable.
  nvim = "nvim",
  -- Buffers larger than this (in bytes) are left to rift's highlighting.
  max_bytes = 300000,
  -- Extra Lua run in the headless Neovim before parsing, for whatever your
  -- config does to tree-sitter outside of queries: custom predicates,
  -- vim.treesitter.language.register(), ...
  nvim_init = "",
  -- Where the scripts, colors and buffer copies go.
  cache_dir = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. sep .. "rift-nvim-syntax",
}

local KIND = "nvim-syntax."
-- The color dump. Renamed whenever its format changes, so an old one left
-- in cache_dir is never read.
local COLORS = "colors-v2.lua"

-- The Neovim side -----------------------------------------------------------

-- Run with the user's full config: every highlight group with its links
-- resolved, as { fg = "rrggbb", bg = "rrggbb", a = attribute bits }. Bits:
-- 1 bold, 2 italic, 4 underline (any kind), 8 strikethrough, 16 reverse,
-- 32 nocombine. A group that sets nothing is {}.
local DUMP_SCRIPT = [==[
local BITS = {
  bold = 1, italic = 2, underline = 4, undercurl = 4, underdouble = 4,
  underdotted = 4, underdashed = 4, strikethrough = 8, reverse = 16,
  nocombine = 32,
}
local out = {}
for name in pairs(vim.api.nvim_get_hl(0, {})) do
  local r = vim.api.nvim_get_hl(0, { name = name, link = false })
  local a = 0
  for k, bit in pairs(BITS) do
    if r[k] and a % (bit * 2) < bit then a = a + bit end
  end
  local parts = {}
  if r.fg then parts[#parts + 1] = string.format('fg = "%06x"', r.fg) end
  if r.bg then parts[#parts + 1] = string.format('bg = "%06x"', r.bg) end
  if a ~= 0 then parts[#parts + 1] = "a = " .. a end
  out[#out + 1] = string.format("[%q] = { %s },", name, table.concat(parts, ", "))
end
table.sort(out)
local path = vim.env.RIFT_NVIM_SYNTAX_OUT
local f = assert(io.open(path .. ".tmp", "wb"))
f:write("return {\n", table.concat(out, "\n"), "\n}\n")
f:close()
os.remove(path)
os.rename(path .. ".tmp", path)
]==]

-- nvim --clean --headless -l highlight.lua <text> <name> <out> <colors> <init>
--
-- Mirrors vim.treesitter.highlighter: every tree (injections included), in
-- for_each_tree order, every capture with its priority. Neovim stacks the
-- captures on a byte from lowest priority to highest (later captures above
-- earlier ones on a tie) and combines them: the top one that sets a color
-- gives the color, and bold/italic/... add up (`nocombine` resets them).
--
-- Writes "start end key" byte runs. key is "rrggbb" (fg), then "-" and
-- attribute letters (b i u s r) and "_rrggbb" (bg) when set. Whitespace
-- only shows underline/strike/reverse/bg, so it joins any run that agrees
-- on those, which keeps the run count down.
local HIGHLIGHT_SCRIPT = [==[
local src, name, out, colors_file, init_file = arg[1], arg[2], arg[3], arg[4], arg[5]
local cfg = vim.fn.stdpath("config")
local data = vim.fn.stdpath("data")

vim.cmd("filetype plugin off | filetype indent off | syntax off")
local dirs = { data .. "/site" }
for _, d in ipairs(vim.fn.glob(data .. "/lazy/*", false, true)) do dirs[#dirs + 1] = d end
dirs[#dirs + 1] = cfg
for _, d in ipairs(dirs) do
  if vim.uv.fs_stat(d) then vim.opt.rtp:prepend(d) end
end
vim.opt.rtp:append(cfg .. "/after")
vim.cmd("augroup filetypedetect | runtime! ftdetect/*.vim ftdetect/*.lua | augroup END")
pcall(require, "nvim-treesitter.query_predicates")
pcall(require, "nvim-treesitter.parsers")
if init_file and init_file ~= "" then dofile(init_file) end

local groups = dofile(colors_file)

local f = assert(io.open(src, "rb"))
local text = f:read("a")
f:close()
local lines = vim.split(text, "\n", { plain = true })

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, name)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_buf_call(buf, function() vim.cmd("filetype detect") end)
local ft = vim.bo[buf].filetype

local o = assert(io.open(out .. ".tmp", "wb"))
local function finish()
  o:close()
  os.remove(out)
  os.rename(out .. ".tmp", out)
end
o:write("ft ", ft, "\n")
local lang = ft ~= "" and (vim.treesitter.language.get_lang(ft) or ft) or nil
local ok, parser = pcall(vim.treesitter.get_parser, buf, lang, { error = false })
if not lang or not ok or not parser then return finish() end
parser:parse(true)

local band, bor = bit.band, bit.bor
local VISIBLE_ON_SPACE = 4 + 8 + 16 -- underline, strikethrough, reverse
local NOCOMBINE = 32

-- @capture.lang -> its group, falling back to parent groups like Neovim
-- does (@keyword.function.lua -> @keyword.function -> @keyword).
local style_cache = {}
local function style_of(group)
  local v = style_cache[group]
  if v == nil then
    v = false
    local g = group
    while g do
      local st = groups[g]
      if st ~= nil then
        v = st
        break
      end
      g = g:match("^(.*)%.[^.]*$")
    end
    style_cache[group] = v
  end
  return v
end

local normal_st = groups.Normal or {}
local normal_fg = normal_st.fg or "ebdbb2"
-- A background equal to Normal's draws nothing.
local function real_bg(bg)
  if bg ~= normal_st.bg then return bg end
end

local line_start, pos = {}, 0
for i, l in ipairs(lines) do
  line_start[i - 1] = pos
  pos = pos + #l + 1
end
local total = pos - 1

local caps, seq = {}, 0
parser:for_each_tree(function(tstree, tree)
  local tlang = tree:lang()
  local q = vim.treesitter.query.get(tlang, "highlights")
  if not q then return end
  for id, node, metadata in q:iter_captures(tstree:root(), buf, 0, -1) do
    local cname = q.captures[id]
    if cname:sub(1, 1) ~= "_" then
      seq = seq + 1
      local st = style_of("@" .. cname .. "." .. tlang)
      if st and (st.fg or st.bg or st.a) then
        local pri = tonumber(metadata.priority or (metadata[id] and metadata[id].priority)) or 100
        if cname == "nospell" then pri = pri + 1 end
        local r = vim.treesitter.get_range(node, buf, metadata[id])
        local s = (line_start[r[1]] or total) + r[2]
        local e = math.min((line_start[r[4]] or total) + r[5], total)
        if e > s then caps[#caps + 1] = { pri, seq, s, e, st } end
      end
    end
  end
end)

-- Stack them bottom to top.
table.sort(caps, function(x, y)
  if x[1] ~= y[1] then return x[1] < y[1] end
  return x[2] < y[2]
end)
local fg, bg, at = {}, {}, {}
for _, c in ipairs(caps) do
  local st = c[5]
  local sfg, sbg, sa = st.fg, real_bg(st.bg), st.a or 0
  local reset = band(sa, NOCOMBINE) ~= 0
  sa = band(sa, NOCOMBINE - 1)
  for b = c[3], c[4] - 1 do
    if sfg then fg[b] = sfg end
    if sbg then bg[b] = sbg end
    if reset then at[b] = sa elseif sa ~= 0 then at[b] = bor(at[b] or 0, sa) end
  end
end

local LETTERS = { { 1, "b" }, { 2, "i" }, { 4, "u" }, { 8, "s" }, { 16, "r" } }
local function key(f, a, k)
  local s = f
  if a ~= 0 then
    s = s .. "-"
    for _, l in ipairs(LETTERS) do
      if band(a, l[1]) ~= 0 then s = s .. l[2] end
    end
  end
  if k then s = s .. "_" .. k end
  return s
end

-- Runs. run_vis is what the run looks like on whitespace.
local run_s, run_k, run_vis, last_e
local function flush()
  if run_s then o:write(run_s, " ", last_e, " ", run_k, "\n") end
  run_s = nil
end
for b = 0, total - 1 do
  local ch = text:byte(b + 1)
  local a = at[b] or 0
  if ch == 32 or ch == 9 or ch == 10 or ch == 13 then
    local vis = key("", band(a, VISIBLE_ON_SPACE), bg[b])
    if run_s and vis == run_vis then
      if vis ~= "" then last_e = b + 1 end
    elseif vis == "" then
      flush()
    else
      flush()
      run_s, run_k, run_vis, last_e = b, key(fg[b] or normal_fg, a, bg[b]), vis, b + 1
    end
  else
    local k = key(fg[b] or normal_fg, a, bg[b])
    if k ~= run_k or not run_s then
      flush()
      run_s, run_k, run_vis = b, k, key("", band(a, VISIBLE_ON_SPACE), bg[b])
    end
    last_e = b + 1
  end
end
flush()
finish()
]==]

-- Files ---------------------------------------------------------------------

local function path(name) return opts.cache_dir .. sep .. name end

local function ensure_cache_dir()
  if file_exists(path("highlight.lua")) then return true end
  if is_windows then
    run_sync("mkdir " .. quote(opts.cache_dir))
  else
    run_sync("mkdir -p " .. quote(opts.cache_dir))
  end
  return true
end

local function nvim_cmd(args)
  local parts = { quote(M.nvim_path) }
  for _, a in ipairs(args) do parts[#parts + 1] = quote(a) end
  return table.concat(parts, " ")
end

local function lua_str(p) return "'" .. p:gsub("\\", "/"):gsub("'", "\\'") .. "'" end

local function dump_args()
  return {
    "--headless",
    "--cmd", "lua vim.env.RIFT_NVIM_SYNTAX_OUT = " .. lua_str(path(COLORS)),
    "-c", "lua dofile(" .. lua_str(path("dump.lua")) .. ")",
    "-c", "qa!",
  }
end

-- Dumps the config's colors now, waiting for it.
local function dump_colors_sync()
  run_sync(nvim_cmd(dump_args()))
end

-- Refreshes the dump in the background (picked up by the next run).
local function dump_colors_async()
  rift.spawn(M.nvim_path, dump_args(), "rift-nvim-syntax:colors")
end

local function write_scripts()
  ensure_cache_dir()
  write_file(path("highlight.lua"), HIGHLIGHT_SCRIPT)
  write_file(path("dump.lua"), DUMP_SCRIPT)
  write_file(path("init.lua"), opts.nvim_init or "")
end

-- Highlighting --------------------------------------------------------------

local applied = {} -- buffer id -> the text its highlights were made for

local function clear()
  rift.annotations.clear(KIND)
end

-- One annotation kind per look ("nvim-syntax.ff922f-b"), registered with
-- its style the first time it's seen, so each annotation is just a kind and
-- a range. No `description`: rift would show it as a hover tooltip.
local ATTRS = { b = "bold", i = "italic", u = "underline", s = "strike", r = "reverse" }
local registered = {}
local function kind_for(key)
  local kind = KIND .. key
  if not registered[key] then
    registered[key] = true
    local fg, rest = key:match("^(%x%x%x%x%x%x)(.*)$")
    local style = { fg = "#" .. fg }
    for l in (rest:match("^%-(%a+)") or ""):gmatch(".") do style[ATTRS[l]] = true end
    local bg = rest:match("_(%x%x%x%x%x%x)$")
    if bg then style.bg = "#" .. bg end
    rift.annotations.register_kind(kind, { style = style })
  end
  return kind
end

-- The current buffer's name and text, or nil when it isn't one to highlight.
local function current()
  if not M.nvim_path then return end
  local kind = rift.buf_kind()
  if kind ~= "file" and kind ~= "scratch" then return end
  local name = rift.get_filepath()
  if not name or name == "" then return end
  return name, table.concat(rift.get_lines(1, -1), "\n")
end

-- Highlights the current buffer; skipped when its text hasn't changed since
-- the last run unless `force`.
function M.highlight(force)
  local name, text = current()
  if not name then return end
  local buf = rift.current_buf()
  if not force and applied[buf] == text then return end
  applied[buf] = text
  if #text > opts.max_bytes then
    clear()
    return
  end
  if not file_exists(path(COLORS)) then dump_colors_sync() end

  write_file(path("buffer.txt"), text)
  os.remove(path("out.txt"))
  run_sync(nvim_cmd({ "--clean", "--headless", "-l", path("highlight.lua"), path("buffer.txt"),
    name, path("out.txt"), path(COLORS), path("init.lua") }))
  local out = read_file(path("out.txt"))
  if not out then return end

  clear()
  local n = 0
  for s, e, k in out:gmatch("(%d+) (%d+) ([%w_%-]+)\n") do
    rift.annotations.add { kind = kind_for(k), range = { tonumber(s), tonumber(e) }, owner = "plugin" }
    n = n + 1
  end
  M.last_count = n
  M.last_filetype = out:match("^ft (%S*)")
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end
  M.nvim_path = which(opts.nvim) or (file_exists(opts.nvim) and opts.nvim) or nil
  if not M.nvim_path then
    rift.notify("warn", "rift-nvim-syntax: " .. opts.nvim .. " not found on PATH")
    return
  end
  write_scripts()

  -- Typed as `:NvimSyntax` it always re-runs; the handlers below pass
  -- "changed" to skip a buffer whose text is unchanged.
  rift.register_command("NvimSyntax", function(args)
    M.highlight(not (args and args[1] == "changed"))
  end, "Re-highlight this buffer the way Neovim does")
  rift.register_command("NvimSyntaxColors", function()
    dump_colors_sync()
    applied = {}
    M.highlight(true)
  end, "Reload colors from the Neovim config, then re-highlight")

  -- Calling setup again only updates options; handlers are registered once.
  if M._registered then return end
  M._registered = true
  if file_exists(path(COLORS)) then dump_colors_async() end
  -- rift cancels event handlers that run past 150 ms, but not commands. So
  -- the handlers only check whether there's work, and queue a `:lua` that
  -- runs the command right after them.
  local function queue(force)
    local name, text = current()
    if not name or (not force and applied[rift.current_buf()] == text) then return end
    rift.exec_action('editor:run:lua _rift_commands["NvimSyntax"].fn({'
      .. (force and '"force"' or '"changed"') .. '})')
  end
  rift.on("BufOpen", function() queue(true) end)
  rift.on("BufEnter", function() queue(false) end)
  rift.on("BufReload", function() queue(true) end)
  -- CursorHold fires once per cursor position. After an edit that leaves
  -- the cursor where it was (r, x, ...) it won't fire again, so
  -- TextChangedCoarse (once per frame after an edit) covers that case.
  -- Typing moves the cursor, so it doesn't run nvim on every keystroke.
  local held -- { buf, row, col } of the last CursorHold, until a move
  rift.on("CursorHold", function(ev)
    held = { ev.buf, ev.row, ev.col }
    queue(false)
  end)
  rift.on("CursorMoved", function(ev)
    if held and (ev.buf ~= held[1] or ev.row ~= held[2] or ev.col ~= held[3]) then held = nil end
  end)
  local function edited_in_place()
    if not held or rift.current_buf() ~= held[1] then return end
    local row, col = rift.get_cursor()
    if row == held[2] and col == held[3] then queue(false) end
  end
  rift.on("TextChangedCoarse", edited_in_place)
  -- Not covered: dd/d{motion}/c{motion} fire no TextChangedCoarse, and
  -- their ModeChanged (and any :lua queued from it) comes before the edit.
end

-- Dropped straight into rift's plugins directory rather than require()d:
-- set up with the defaults.
if not MODULE then M.setup() end

return M
