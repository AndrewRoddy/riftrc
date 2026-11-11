-- `J` and `gJ`: join lines like Neovim. rift has no join command at all.
--
-- A port of Neovim's do_join(), checked against Neovim 0.11 (text and cursor)
-- on 31 cases:
--
--   J   Joins the line below onto this one. Leading whitespace of the joined
--       line is removed and one space put in its place, except when the
--       joined text is empty or starts with `)`, when this line is empty,
--       or ends in a space or tab. 'nojoinspaces': one space after `.` too.
--   gJ  Joins without adding or removing whitespace.
--
-- Both remove the comment leader of the joined line when the line it is
-- joined onto has a comment in it ('formatoptions' j, on by default in
-- Neovim): `-- a` + `-- b` -> `-- a b`, `x = 1 -- a` + `-- b` -> `x = 1 -- a b`.
-- In /* */ comments the ` * ` of middle lines goes too.
--
-- The cursor ends on the join point (the inserted space). On the last line
-- nothing happens.
--
-- rift doesn't pass counts to plugins, so `3J` joins two lines. Use
-- `:Join 3` / `:JoinRaw 3` for more.
local M = {}
local MODULE = ...

-- Helpers -------------------------------------------------------------------

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

-- Comment leaders, a subset of Neovim's 'comments' per filetype. Keys are
-- rift filetype names and file extensions (a buffer has no filetype until
-- its syntax has loaded, and many extensions have no rift grammar).
-- `block` means /* */ comments whose middle lines start with `*`.
local C_LIKE = { line = { "//" }, block = true }
local HASH = { line = { "#" } }
local LEADERS = {
  c = C_LIKE, h = C_LIKE, cpp = C_LIKE, cc = C_LIKE, cxx = C_LIKE, hpp = C_LIKE,
  c_sharp = C_LIKE, cs = C_LIKE, java = C_LIKE, go = C_LIKE, php = C_LIKE,
  javascript = C_LIKE, js = C_LIKE, jsx = C_LIKE, mjs = C_LIKE, cjs = C_LIKE,
  typescript = C_LIKE, ts = C_LIKE, tsx = C_LIKE, mts = C_LIKE, cts = C_LIKE,
  json = C_LIKE, jsonc = C_LIKE, kt = C_LIKE, kotlin = C_LIKE, swift = C_LIKE,
  dart = C_LIKE, scala = C_LIKE, scss = C_LIKE, less = C_LIKE, proto = C_LIKE,
  zig = { line = { "//" } },
  rust = { line = { "///", "//!", "//" }, block = true },
  css = { line = {}, block = true },
  lua = { line = { "---", "--" } },
  sql = { line = { "--" }, block = true },
  hs = { line = { "--" } }, elm = { line = { "--" } },
  python = HASH, py = HASH, ruby = HASH, rb = HASH, bash = HASH, sh = HASH,
  zsh = HASH, yaml = HASH, yml = HASH, toml = HASH, conf = HASH, cfg = HASH,
  fish = HASH, ps1 = HASH, psm1 = HASH, powershell = HASH, r = HASH, pl = HASH,
  nix = { line = { "#" }, block = true }, ex = HASH, exs = HASH, cmake = HASH,
  mk = HASH, make = HASH, makefile = HASH, dockerfile = HASH, gitignore = HASH,
  env = HASH,
  ini = { line = { ";" } },
  vim = { line = { '"' } },
  lisp = { line = { ";;" } }, clj = { line = { ";;" } }, el = { line = { ";;" } },
  erl = { line = { "%" } }, tex = { line = { "%" } },
}

-- The current buffer's filetype, falling back to its extension (or the
-- whole name for Makefile, Dockerfile, .gitignore).
local function filetype()
  local ft = rift.get_filetype()
  if ft then return ft end
  local path = rift.get_filepath()
  if not path then return nil end
  local name = path:match("[^/\\]+$"):lower()
  return name:match("^.+%.([^.]+)$") or (name:gsub("^%.", ""))
end

local NONE = { line = {}, block = false }

local function leaders()
  local ft = filetype()
  return (ft and LEADERS[ft]) or NONE
end

local function starts_with(s, prefix) return s:sub(1, #prefix) == prefix end

-- Whether `line` contains a comment that is still open at the end of the
-- line: Neovim looks at the last comment leader in it (preceded by
-- whitespace or at the start); a `*/` means the comment was closed.
local function has_comment(line, L)
  local best, best_is_end = nil, false
  local function consider(pos, is_end)
    if pos > 1 and not line:sub(pos - 1, pos - 1):match("%s") then return end
    if not best or pos > best then best, best_is_end = pos, is_end end
  end
  for _, leader in ipairs(L.line) do
    local i = 1
    while true do
      local s = line:find(leader, i, true)
      if not s then break end
      consider(s, false)
      i = s + 1
    end
  end
  if L.block then
    local i = 1
    while true do
      local s = line:find("/*", i, true)
      if not s then break end
      consider(s, false)
      i = s + 1
    end
    i = 1
    while true do
      local s = line:find("*/", i, true)
      if not s then break end
      -- `*/` closes even when glued to text: "text */"
      if not best or s > best then best, best_is_end = s, true end
      i = s + 1
    end
    -- A middle line: " * text"
    local ws = line:match("^%s*")
    if line:sub(#ws + 1, #ws + 1) == "*" and line:sub(#ws + 2, #ws + 2) ~= "/" then
      consider(#ws + 1, false)
    end
  end
  return best ~= nil and not best_is_end
end

-- Byte length of the comment leader at the start of `line` (indentation
-- included), plus the whitespace after it when `include_space`. 0 if the
-- line doesn't start with a leader. End leaders (`*/`) are never removed.
local function leader_len(line, L, include_space)
  local ws = line:match("^%s*")
  local rest = line:sub(#ws + 1)
  local len
  for _, leader in ipairs(L.line) do
    if starts_with(rest, leader) then len = #ws + #leader break end
  end
  if not len and L.block and starts_with(rest, "*") and not starts_with(rest, "*/") then
    len = #ws + 1
  end
  if not len then return 0 end
  if include_space then len = len + #(line:sub(len + 1):match("^%s*")) end
  return len
end

-- Joins `count` lines (at least 2) starting at the cursor. `insert_space`
-- is J (true) or gJ (false).
function M.join(count, insert_space)
  local kind = rift.buf_kind()
  if kind ~= "file" and kind ~= "scratch" then return end
  local row = rift.get_cursor()
  local all = rift.get_lines(1, -1)
  local total = #all
  -- rift counts the empty line after a final newline; Neovim doesn't.
  if total > 1 and all[total] == "" then total = total - 1 end

  count = math.max(2, count or 2)
  if row + count - 1 > total then
    if count <= 2 then return end -- on the last line: nothing to join
    count = total - row + 1
  end

  local L = leaders()
  local result = all[row]
  local prev_was_comment = has_comment(result, L)
  local join_col = 0
  for t = 2, count do
    local curr = all[row + t - 1]
    local is_comment = has_comment(curr, L)
    if prev_was_comment and is_comment then
      curr = curr:sub(leader_len(curr, L, insert_space) + 1)
    end
    prev_was_comment = is_comment

    local space = ""
    if insert_space then
      curr = curr:gsub("^%s+", "")
      local last = result:sub(-1)
      if curr ~= "" and curr:sub(1, 1) ~= ")" and result ~= "" and last ~= "\t"
        and last ~= " " then
        space = " "
      end
    end
    join_col = char_len(result)
    result = result .. space .. curr
  end

  set_lines(row, row + count - 1, { result })
  rift.set_cursor(row, math.max(0, math.min(join_col, char_len(result) - 1)))
end

function M.setup()
  local function count_of(args) return tonumber(args[1] or "") or 2 end
  rift.register_command("Join", function(args) M.join(count_of(args), true) end,
    "Join [count] lines like J (default 2)")
  rift.register_command("JoinRaw", function(args) M.join(count_of(args), false) end,
    "Join [count] lines like gJ, keeping whitespace (default 2)")
  map("n", "J", "Join")
  map("n", "gJ", "JoinRaw")
end

M._has_comment = has_comment
M._leader_len = leader_len

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
