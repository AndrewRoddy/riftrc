-- Comment.nvim for rift: toggle line (`gc`) and block (`gb`) comments.
local M = {}

-- Comment strings per filetype as { line, block }, each "left%sright".
-- Keys are rift language names first, then bare file extensions for files
-- rift has no grammar for (which is when `rift.get_filetype()` is nil).
local commentstrings = {
  c = { "//%s", "/*%s*/" },
  cpp = { "//%s", "/*%s*/" },
  c_sharp = { "//%s", "/*%s*/" },
  java = { "//%s", "/*%s*/" },
  javascript = { "//%s", "/*%s*/" },
  typescript = { "//%s", "/*%s*/" },
  tsx = { "//%s", "/*%s*/" },
  go = { "//%s", "/*%s*/" },
  rust = { "//%s", "/*%s*/" },
  zig = { "//%s" },
  php = { "//%s", "/*%s*/" },
  css = { "/*%s*/", "/*%s*/" },
  json = { "//%s", "/*%s*/" },
  lua = { "--%s", "--[[%s]]" },
  sql = { "--%s", "/*%s*/" },
  python = { "#%s" },
  ruby = { "#%s" },
  bash = { "#%s" },
  yaml = { "#%s" },
  html = { "<!--%s-->", "<!--%s-->" },
  markdown = { "<!--%s-->", "<!--%s-->" },
  svelte = { "<!--%s-->", "<!--%s-->" },

  -- Extensions without a rift grammar
  h = { "//%s", "/*%s*/" },
  hpp = { "//%s", "/*%s*/" },
  kt = { "//%s", "/*%s*/" },
  swift = { "//%s", "/*%s*/" },
  dart = { "//%s", "/*%s*/" },
  scala = { "//%s", "/*%s*/" },
  scss = { "//%s", "/*%s*/" },
  less = { "//%s", "/*%s*/" },
  jsonc = { "//%s", "/*%s*/" },
  proto = { "//%s", "/*%s*/" },
  toml = { "#%s" },
  ini = { ";%s" },
  conf = { "#%s" },
  cfg = { "#%s" },
  fish = { "#%s" },
  ps1 = { "#%s", "<#%s#>" },
  psm1 = { "#%s", "<#%s#>" },
  r = { "#%s" },
  pl = { "#%s" },
  nix = { "#%s", "/*%s*/" },
  ex = { "#%s" },
  exs = { "#%s" },
  cmake = { "#%s" },
  mk = { "#%s" },
  makefile = { "#%s" },
  dockerfile = { "#%s" },
  gitignore = { "#%s" },
  env = { "#%s" },
  hs = { "--%s", "{-%s-}" },
  elm = { "--%s", "{-%s-}" },
  vim = { '"%s' },
  lisp = { ";;%s" },
  clj = { ";;%s" },
  scm = { ";;%s" },
  el = { ";;%s" },
  erl = { "%%%s" },
  tex = { "%%%s" },
  m = { "%%%s" },
  ml = { "(*%s*)", "(*%s*)" },
  bat = { "REM %s" },
  cmd = { "REM %s" },
  xml = { "<!--%s-->", "<!--%s-->" },
  xhtml = { "<!--%s-->", "<!--%s-->" },
  vue = { "<!--%s-->", "<!--%s-->" },
  razor = { "@*%s*@", "@*%s*@" },
  cshtml = { "@*%s*@", "@*%s*@" },
  spl = { "`comment(%s)`" },
  splunk = { "`comment(%s)`" },
}

-- Strings mean "the same as this other entry". Covers rift's own extensions
-- too, since a buffer has no filetype until its syntax has loaded.
local aliases = {
  rs = "rust",
  py = "python",
  rb = "ruby",
  js = "javascript",
  ts = "typescript",
  cs = "c_sharp",
  cc = "cpp",
  cxx = "cpp",
  bash = "bash",
  mjs = "javascript",
  cjs = "javascript",
  jsx = "javascript",
  mts = "typescript",
  cts = "typescript",
  htm = "html",
  yml = "yaml",
  sh = "bash",
  zsh = "bash",
  md = "markdown",
}

local opts = {
  padding = true,
  mappings = true,
}

local function filetype()
  local ft = rift.get_filetype()
  if ft then return ft end
  local path = rift.get_filepath()
  if not path then return nil end
  local name = rift.fs.basename(path):lower()
  -- Dotless names like "Makefile"/"Dockerfile", and dotfiles like ".gitignore"
  local ext = name:match("^.+%.([^.]+)$") or name:gsub("^%.", "")
  return ext
end

-- Splits "left%sright" into its trimmed halves.
local function split(cs)
  local left, right = cs:match("^(.-)%%s(.-)$")
  if not left then return nil end
  return (left:gsub("%s+$", "")), (right:gsub("^%s+", ""))
end

local function resolve(kind)
  local ft = filetype()
  if not ft then return nil, "no filetype" end
  ft = aliases[ft] or ft
  local entry = M.commentstrings[ft]
  if not entry then return nil, "no commentstring for '" .. ft .. "'" end
  local cs = kind == "block" and entry[2] or entry[1]
  if not cs then return nil, "no block commentstring for '" .. ft .. "'" end
  return split(cs)
end

local function escape(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function is_blank(line)
  return not line:find("%S")
end

local function pad()
  return opts.padding and " " or ""
end

-- Number of characters (not bytes) in `s`, so cursor columns stay right on
-- non-ASCII lines.
local function chars(s)
  return utf8.len(s) or #s
end

-- Line comments ---------------------------------------------------------------

local function line_is_commented(line, left, right)
  local body = line:match("^%s*" .. escape(left) .. "(.*)$")
  if not body then return false end
  if right == "" then return true end
  return body:match(escape(right) .. "%s*$") ~= nil
end

local function uncomment_line(line, left, right)
  local indent, body = line:match("^(%s*)" .. escape(left) .. "(.*)$")
  if right ~= "" then
    body = body:gsub("%s?" .. escape(right) .. "%s*$", "")
  end
  body = body:gsub("^ ", "", 1)
  return indent .. body
end

local function comment_line(line, left, right, indent_len)
  local indent = line:sub(1, indent_len)
  local body = line:sub(indent_len + 1)
  local tail = right ~= "" and (pad() .. right) or ""
  return indent .. left .. pad() .. body .. tail
end

-- Toggles line comments over `lines` as one unit, Comment.nvim style: if every
-- non-blank line is commented they are all uncommented, otherwise all are
-- commented at the shallowest indent. Blank lines are left alone.
local function toggle_lines(lines, left, right)
  local all_commented, any = true, false
  local min_indent
  for _, line in ipairs(lines) do
    if not is_blank(line) then
      any = true
      if not line_is_commented(line, left, right) then all_commented = false end
      local indent = #line:match("^%s*")
      if not min_indent or indent < min_indent then min_indent = indent end
    end
  end
  if not any then return lines end

  local out = {}
  for i, line in ipairs(lines) do
    if is_blank(line) then
      out[i] = line
    elseif all_commented then
      out[i] = uncomment_line(line, left, right)
    else
      out[i] = comment_line(line, left, right, min_indent)
    end
  end
  return out
end

-- Block comments --------------------------------------------------------------

-- Wraps (or unwraps) lines[1] from byte `scol` through lines[#lines] up to and
-- including byte `ecol` in one block comment.
local function toggle_block(lines, left, right, scol, ecol)
  local first, last = lines[1], lines[#lines]
  local n = #lines
  scol = scol or #first:match("^%s*") + 1
  ecol = ecol or #last:gsub("%s+$", "")

  local head = first:sub(scol)
  local tail = (n == 1 and first or last):sub(1, ecol)
  if head:sub(1, #left) == left and tail:sub(-#right) == right then
    local out = { table.unpack(lines) }
    if n == 1 then
      local inner = first:sub(scol + #left, ecol - #right)
      inner = inner:gsub("^ ", "", 1):gsub(" $", "", 1)
      out[1] = first:sub(1, scol - 1) .. inner .. first:sub(ecol + 1)
    else
      out[1] = first:sub(1, scol - 1) .. first:sub(scol + #left):gsub("^ ", "", 1)
      out[n] = last:sub(1, ecol - #right):gsub(" $", "", 1) .. last:sub(ecol + 1)
    end
    return out
  end

  local out = { table.unpack(lines) }
  if n == 1 then
    out[1] = first:sub(1, scol - 1) .. left .. pad() .. first:sub(scol, ecol)
      .. pad() .. right .. first:sub(ecol + 1)
  else
    out[1] = first:sub(1, scol - 1) .. left .. pad() .. first:sub(scol)
    out[n] = last:sub(1, ecol) .. pad() .. right .. last:sub(ecol + 1)
  end
  return out
end

-- Editing ---------------------------------------------------------------------

local function editable()
  if rift.buf_kind() ~= "file" then
    rift.notify("warn", "Comment: not a file buffer")
    return false
  end
  return true
end

-- Replaces lines [s, e] with `new` and keeps the cursor on the same text.
local function apply(s, e, new, cursor_row, cursor_col)
  local old = rift.get_lines(s, e)
  rift.replace_lines(s, e, new)
  if cursor_row and cursor_row >= s and cursor_row <= e then
    local i = cursor_row - s + 1
    local delta = chars(new[i] or "") - chars(old[i] or "")
    rift.set_cursor(cursor_row, math.max(0, cursor_col + delta))
  elseif cursor_row then
    rift.set_cursor(cursor_row, cursor_col)
  end
end

-- Toggles comments over lines [s, e] (1-indexed, inclusive).
function M.toggle_range(kind, s, e)
  if not editable() then return end
  local left, right = resolve(kind)
  if not left then
    rift.notify("warn", "Comment: " .. right)
    return
  end
  local total = rift.get_line_count()
  s, e = math.max(1, math.min(s, e)), math.min(total, math.max(s, e))
  local lines = rift.get_lines(s, e)
  local new = kind == "block" and toggle_block(lines, left, right)
    or toggle_lines(lines, left, right)
  local row, col = rift.get_cursor()
  apply(s, e, new, row, col)
end

function M.toggle_current(kind, count)
  local row = rift.get_cursor()
  M.toggle_range(kind, row, row + math.max(1, count or 1) - 1)
end

-- Character columns from rift are converted to byte positions in `line`.
local function byte_col(line, col)
  return utf8.offset(line, col + 1) or #line + 1
end

-- Comments every selected region: the live Visual selection plus any banked
-- regions. `gc` always works on whole lines; `gb` wraps exactly the selected
-- characters of a charwise selection.
function M.toggle_selection(kind)
  if not editable() then return end
  local regions = rift.get_selection()
  if #regions == 0 then
    rift.notify("warn", "Comment: nothing selected")
    return
  end
  local left, right = resolve(kind)
  if not left then
    rift.notify("warn", "Comment: " .. right)
    return
  end

  -- Leave Visual and drop the banked regions before editing: the first
  -- mode:normal banks the live selection, the second clears the bank.
  rift.exec_action("mode:normal")
  rift.exec_action("mode:normal")

  -- Bottom-up so earlier edits never shift later line numbers.
  table.sort(regions, function(a, b) return a.start_row > b.start_row end)
  local first_row = regions[#regions].start_row
  for _, r in ipairs(regions) do
    local lines = rift.get_lines(r.start_row, r.end_row)
    local new
    if kind == "block" and r.kind == "char" then
      local scol = byte_col(lines[1], r.start_col)
      local last = lines[#lines]
      -- end_col is inclusive: take every byte of the last selected character.
      local ecol = (utf8.offset(last, r.end_col + 2) or #last + 1) - 1
      new = toggle_block(lines, left, right, scol, ecol)
    elseif kind == "block" then
      new = toggle_block(lines, left, right)
    else
      new = toggle_lines(lines, left, right)
    end
    rift.replace_lines(r.start_row, r.end_row, new)
  end
  local indent = #(rift.get_lines(first_row, first_row)[1] or ""):match("^%s*")
  rift.set_cursor(first_row, indent)
end

-- `gcap`/`gcip`: the paragraph around the cursor, with (a) or without (i)
-- the blank lines after it.
function M.toggle_paragraph(around)
  local row = rift.get_cursor()
  local total = rift.get_line_count()
  local lines = rift.get_lines(1, total)
  if is_blank(lines[row] or "") then return end
  local s, e = row, row
  while s > 1 and not is_blank(lines[s - 1]) do s = s - 1 end
  while e < total and not is_blank(lines[e + 1]) do e = e + 1 end
  if around then
    while e < total and is_blank(lines[e + 1]) do e = e + 1 end
  end
  M.toggle_range("line", s, e)
end

-- `gco` / `gcO` / `gcA`: start a new comment and enter insert mode.
function M.insert_comment(where)
  if not editable() then return end
  local left, right = resolve("line")
  if not left then
    rift.notify("warn", "Comment: " .. right)
    return
  end
  local row = rift.get_cursor()
  local line = rift.get_lines(row, row)[1] or ""
  local tail = right ~= "" and (pad() .. right) or ""

  if where == "eol" then
    local body = line:gsub("%s+$", "")
    local sep = body == "" and "" or " "
    local new = body .. sep .. left .. pad()
    rift.replace_lines(row, row, { new .. tail })
    rift.set_cursor(row, chars(new))
    rift.exec_action("mode:insert")
    return
  end

  local indent = line:match("^%s*")
  local new = indent .. left .. pad()
  if where == "below" then
    rift.replace_lines(row, row, { line, new .. tail })
    row = row + 1
  else
    rift.replace_lines(row, row, { new .. tail, line })
  end
  rift.set_cursor(row, chars(new))
  rift.exec_action("mode:insert")
end

-- Setup -----------------------------------------------------------------------

local function count_arg(args)
  return tonumber(args[1] or "") or 1
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do
    if k == "commentstrings" then
      for ft, cs in pairs(v) do M.commentstrings[ft] = cs end
    else
      opts[k] = v
    end
  end

  rift.register_command("CommentToggle", function(args)
    M.toggle_current("line", count_arg(args))
  end, "Toggle line comments on [count] lines")
  rift.register_command("CommentBlockToggle", function(args)
    M.toggle_current("block", count_arg(args))
  end, "Toggle a block comment around [count] lines")
  rift.register_command("CommentSelection", function()
    M.toggle_selection("line")
  end, "Toggle line comments on the selection")
  rift.register_command("CommentBlockSelection", function()
    M.toggle_selection("block")
  end, "Toggle a block comment around the selection")
  rift.register_command("CommentDown", function(args)
    M.toggle_current("line", count_arg(args) + 1)
  end, "Toggle line comments from the cursor down [count] lines")
  rift.register_command("CommentUp", function(args)
    local row = rift.get_cursor()
    M.toggle_range("line", row - count_arg(args), row)
  end, "Toggle line comments from the cursor up [count] lines")
  rift.register_command("CommentToTop", function()
    M.toggle_range("line", 1, (rift.get_cursor()))
  end, "Toggle line comments from the cursor to the first line")
  rift.register_command("CommentToBottom", function()
    M.toggle_range("line", (rift.get_cursor()), rift.get_line_count())
  end, "Toggle line comments from the cursor to the last line")
  rift.register_command("CommentParagraph", function(args)
    M.toggle_paragraph(args[1] == "around")
  end, "Toggle line comments on the paragraph (pass 'around' to include trailing blanks)")
  rift.register_command("CommentInsert", function(args)
    M.insert_comment(args[1] or "below")
  end, "Start a comment: below | above | eol")

  if not opts.mappings then return end

  rift.map("n", "gcc", "editor:run:CommentToggle")
  rift.map("n", "gbc", "editor:run:CommentBlockToggle")
  rift.map("v", "gc", "editor:run:CommentSelection")
  rift.map("v", "gb", "editor:run:CommentBlockSelection")

  -- rift has no operator-pending hook for plugins, so the common gc{motion}
  -- forms are spelled out. Counts go between gc and the motion: gc3j.
  rift.map("n", "gcj", "editor:run:CommentDown 1")
  rift.map("n", "gck", "editor:run:CommentUp 1")
  for n = 1, 9 do
    rift.map("n", "gc" .. n .. "j", "editor:run:CommentDown " .. n)
    rift.map("n", "gc" .. n .. "k", "editor:run:CommentUp " .. n)
  end
  rift.map("n", "gcgg", "editor:run:CommentToTop")
  rift.map("n", "gcG", "editor:run:CommentToBottom")
  rift.map("n", "gcip", "editor:run:CommentParagraph")
  rift.map("n", "gcap", "editor:run:CommentParagraph around")

  rift.map("n", "gco", "editor:run:CommentInsert below")
  rift.map("n", "gcO", "editor:run:CommentInsert above")
  rift.map("n", "gcA", "editor:run:CommentInsert eol")
end

M.commentstrings = commentstrings
M._toggle_lines = toggle_lines
M._toggle_block = toggle_block

return M
