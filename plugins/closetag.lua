-- vim-closetag for rift: typing `>` to finish an opening tag inserts its
-- closing tag after the cursor. Typing `>` again right away moves the closing
-- tag onto its own line with the cursor on an indented line in between.
local M = {}

local opts = {
  -- File extensions the plugin is active for (vim-closetag's closetag_filenames)
  extensions = { "html", "htm", "xhtml", "xml", "jsx", "tsx", "vue", "svelte", "php" },
  -- Elements that never get a closing tag, except in the extensions below
  void_elements = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
  },
  -- Where every element is closed, void or not (vim-closetag's xhtml list)
  xhtml_extensions = { "xhtml", "xml" },
}

local enabled_ext, void, xhtml = {}, {}, {}
local mapped = false
local disabled = false

local function set_of(list)
  local set = {}
  for _, v in ipairs(list) do set[v:lower()] = true end
  return set
end

local function ext_of(path)
  local ext = path and path:match("%.([^.\\/]+)$")
  return ext and ext:lower()
end

local function path_of(buf)
  for _, b in ipairs(rift.get_buf_list()) do
    if b.id == buf then return b.path end
  end
  return nil
end

local function chars(s)
  return utf8.len(s) or #s
end

-- Byte length of the first `col` characters of `line`.
local function byte_len(line, col)
  local off = utf8.offset(line, col + 1)
  return off and off - 1 or #line
end

-- Drops quoted strings and `{ ... }` expressions from a tag's attribute text.
-- Returns nil when one is still open, i.e. the cursor is inside it.
local function strip_values(attrs)
  local out, depth, quote = {}, 0, nil
  for i = 1, #attrs do
    local c = attrs:sub(i, i)
    if quote then
      if c == quote then quote = nil end
    elseif c == '"' or c == "'" or c == "`" then
      quote = c
    elseif c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
      if depth < 0 then return nil end
    elseif depth == 0 then
      out[#out + 1] = c
    end
  end
  if quote or depth ~= 0 then return nil end
  return table.concat(out)
end

-- If `before` (the text left of the cursor) ends inside an opening tag that
-- the `>` being typed would complete, returns the tag name.
function M.unclosed_tag(before, ext)
  local starts = {}
  for pos in before:gmatch("()<[%a_]") do starts[#starts + 1] = pos end

  -- Nearest `<` first; ones inside a JSX expression of an outer tag are skipped.
  for i = #starts, 1, -1 do
    local s = starts[i]
    local name, attrs = before:match("^<([%a_][%w_:%.%-]*)(.*)$", s)
    local prev = s > 1 and before:sub(s - 1, s - 1) or ""
    -- `Array<string`, `useState<T`: generics, not tags
    if not prev:match("[%w_%.%]%)]") then
      local plain = strip_values(attrs)
      if plain then
        -- The tag was already closed somewhere before the cursor
        if plain:find(">") then return nil end
        -- `<br /`: already self-closing
        if plain:match("/%s*$") then return nil end
        if void[name:lower()] and not xhtml[ext] then return nil end
        return name
      end
    end
  end
  return nil
end

local function indent_unit()
  if rift.get_expand_tabs() then
    return string.rep(" ", rift.get_tab_width())
  end
  return "\t"
end

function M.on_gt()
  local row, col = rift.get_cursor()
  local line = rift.get_current_line()
  local split = byte_len(line, col)
  local before, after = line:sub(1, split), line:sub(split + 1)
  local ext = ext_of(rift.get_filepath())

  if disabled or not enabled_ext[ext] then
    rift.insert(">")
    return
  end

  -- Second `>` straight after an auto-close: `<div>|</div>` becomes
  --   <div>
  --       |
  --   </div>
  local open = before:match("<([%a_][%w_:%.%-]*)[^<>]*>$")
  if open and after:sub(1, #open + 3) == "</" .. open .. ">" then
    local indent = line:match("^%s*")
    local inner = indent .. indent_unit()
    rift.replace_lines(row, row, { before, inner, indent .. after })
    rift.set_cursor(row + 1, chars(inner))
    return
  end

  local name = M.unclosed_tag(before, ext)
  if name then
    rift.insert("></" .. name .. ">")
    rift.set_cursor(row, col + 1)
  else
    rift.insert(">")
  end
end

-- Maps `>` in insert mode only while a matching file is focused, so other
-- filetypes keep typing `>` natively (and keep their dot-repeat intact).
local function refresh(path)
  local want = enabled_ext[ext_of(path)] == true
  if want and not mapped then
    rift.map("i", ">", "editor:run:CloseTagGt")
  elseif mapped and not want then
    rift.unmap("i", ">")
  end
  mapped = want
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end
  enabled_ext = set_of(opts.extensions)
  void = set_of(opts.void_elements)
  xhtml = set_of(opts.xhtml_extensions)

  rift.register_command("CloseTagGt", M.on_gt, "Insert '>' and close the tag (insert-mode '>')")
  rift.register_command("CloseTagToggle", function()
    disabled = not disabled
    rift.notify("info", "closetag " .. (disabled and "disabled" or "enabled"))
  end, "Turn tag auto-closing off/on")

  refresh(rift.get_filepath())

  -- Calling setup again only updates options; handlers are registered once.
  if M._registered then return end
  M._registered = true
  rift.on("BufEnter", function(ev) refresh(path_of(ev.buf)) end)
  rift.on("BufOpen", function(ev) refresh(ev.path or path_of(ev.buf)) end)
end

return M
