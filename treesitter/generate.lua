-- Builds rift's treesitter setup from Neovim's, so highlighting matches.
--
-- Run from Neovim, with your normal config loaded (it reads your colors):
--
--   nvim --headless -c "luafile %APPDATA%/rift/plugins/riftrc/treesitter/generate.lua" -c "qa!"
--
-- For every parser nvim-treesitter has installed it:
--   * copies the compiled parser into parsers/ (rift loads it with
--     rift.register_grammar, replacing rift's bundled grammar, so the syntax
--     tree has the same node names the queries were written for);
--   * collects the highlights/injections query files exactly as Neovim does
--     (vim.treesitter.query.get_files: `; inherits:` and your own `; extends`);
--   * rewrites the parts of those queries only Neovim understands;
--   * renames every highlight capture so rift draws it in the color Neovim
--     draws it in (see "Colors" below);
-- and writes manifest.lua, which plugins/treesitter.lua loads at startup.
--
-- Colors: rift has no way to set a color per capture. Its theme maps a few
-- capture names to colors, and a capture name falls back by dropping
-- `.suffix` parts. So a capture Neovim draws #8ec07c becomes
-- `@function.<original_name>`, because rift's gruvbox theme draws `function`
-- in #8ec07c. Colors the theme does not have go to the nearest one it does
-- (listed in REPORT.md).

local script = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local OUT = script:match("(.*)/[^/]+$")
local is_windows = vim.fn.has("win32") == 1

-- rift's gruvbox theme (src/color/theme/mod.rs, gruvbox_syntax): capture name
-- whose color is the one given. `none` is the theme's foreground.
local PALETTE = {
  { "none", "#ebdbb2" },
  { "function", "#8ec07c" },
  { "string", "#b8bb26" },
  { "number", "#d4879c" },
  { "comment", "#928374" },
  { "punctuation", "#a89984" },
  { "variable", "#c3d2d5" },
  { "ui.lsp.ok", "#83a598" },
  { "ui.lsp.warn", "#fabd2f" },
  { "ui.lsp.error", "#fb4934" },
}

-- Colors to send somewhere other than the nearest palette entry.
-- #ff922f (keywords) is nearest to #fabd2f, but that is the type color, so
-- keywords and types would look the same. Red keeps them apart.
local OVERRIDES = {
  ["#ff922f"] = "ui.lsp.error",
}

-- Extensions rift should open with each parser. rift picks the language by
-- extension only, so parsers for extensionless files (Dockerfile, Makefile,
-- .gitignore) still load for injections but are not tied to a file here.
local EXTENSIONS = {
  bash = { "sh", "bash", "zsh" },
  c = { "c", "h" },
  c_sharp = { "cs" },
  cpp = { "cc", "cpp", "cxx", "hpp", "hh", "hxx" },
  css = { "css" },
  csv = { "csv" },
  diff = { "diff", "patch" },
  dockerfile = { "dockerfile" },
  git_config = { "gitconfig" },
  go = { "go" },
  graphql = { "graphql", "gql" },
  html = { "html", "htm" },
  ini = { "ini" },
  java = { "java" },
  javascript = { "js", "jsx", "mjs", "cjs" },
  json = { "json" },
  jsonc = { "jsonc" },
  kotlin = { "kt", "kts" },
  lua = { "lua" },
  make = { "mk", "mak" },
  markdown = { "md", "markdown" },
  powershell = { "ps1", "psm1", "psd1" },
  psu = { "psu" },
  python = { "py", "pyi" },
  query = { "scm" },
  razor = { "razor", "cshtml" },
  rust = { "rs" },
  scss = { "scss" },
  splunk = { "spl", "splunk" },
  sql = { "sql" },
  svelte = { "svelte" },
  toml = { "toml" },
  tsx = { "tsx" },
  typescript = { "ts", "mts", "cts" },
  vim = { "vim" },
  vue = { "vue" },
  xml = { "xml", "xsd", "xsl", "xslt", "svg", "csproj", "props", "targets", "resx" },
  yaml = { "yaml", "yml" },
}

-- Neovim-only predicates rift's tree-sitter can't evaluate. It would ignore
-- them and over-match, so patterns using them are dropped instead.
local UNSUPPORTED = {
  ["has-ancestor?"] = true, ["not-has-ancestor?"] = true,
  ["has-parent?"] = true, ["not-has-parent?"] = true,
  ["contains?"] = true, ["not-contains?"] = true,
  ["kind-eq?"] = true, ["not-kind-eq?"] = true,
  ["set-lang-from-mimetype!"] = true,
  ["cl-standard-macro?"] = true, ["cl-standard-function?"] = true,
}

-- Directives that only change Neovim's behavior; removed, pattern kept.
local STRIP = {
  ["downcase!"] = true, ["gsub!"] = true, ["trim!"] = true,
  ["splunkxml?"] = true, -- your xml/injections.scm: rift has no splunkxml filetype
}

-- Captures that carry no color in Neovim (spell checking, concealing).
local NO_COLOR = { spell = true, nospell = true, conceal = true, conceal_lines = true }

local report = { approx = {}, dropped = {}, errors = {} }

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------

local function hex_to_rgb(h)
  return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

local normal_fg = (function()
  local fg = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("Normal")), "fg#")
  return fg ~= "" and fg:lower() or "#ebdbb2"
end)()

-- The color Neovim draws `@capture` in for `lang`, the same lookup its
-- highlighter does (`@capture.lang`, falling back through the dotted parents).
local function nvim_color(lang, capture)
  local id = vim.api.nvim_get_hl_id_by_name("@" .. capture .. "." .. lang)
  local fg = vim.fn.synIDattr(vim.fn.synIDtrans(id), "fg#")
  return fg ~= "" and fg:lower() or normal_fg
end

local function palette_name(hex)
  if OVERRIDES[hex] then return OVERRIDES[hex], false end
  local r, g, b = hex_to_rgb(hex)
  local best, best_d
  for _, p in ipairs(PALETTE) do
    local pr, pg, pb = hex_to_rgb(p[2])
    local d = (r - pr) ^ 2 + (g - pg) ^ 2 + (b - pb) ^ 2
    if not best_d or d < best_d then best, best_d = p[1], d end
  end
  return best, best_d <= 12 -- within a couple of steps per channel counts as exact
end

local renamed = {}
local function rift_capture(lang, capture)
  local key = lang .. "\0" .. capture
  if renamed[key] then return renamed[key] end
  local hex = nvim_color(lang, capture)
  local name, exact = palette_name(hex)
  if not exact then
    local k = hex .. " -> " .. name
    report.approx[k] = report.approx[k] or {}
    report.approx[k][#report.approx[k] + 1] = lang .. ":@" .. capture
  end
  -- The original name stays on as a suffix, which rift's lookup drops.
  renamed[key] = name .. "." .. capture:gsub("[^%w]", "_")
  return renamed[key]
end

---------------------------------------------------------------------------
-- Lua patterns -> regex (for #lua-match?)
---------------------------------------------------------------------------

local CLASS = {
  a = "A-Za-z", d = "0-9", l = "a-z", u = "A-Z", w = "A-Za-z0-9",
  x = "0-9A-Fa-f", s = [[\t\n\v\f\r ]], p = [[!-/:-@\[-`{-~]], c = [[\x00-\x1f\x7f]],
}

local function regex_escape(c)
  return c:match("[%^%$%.%*%+%?%(%)%[%]%{%}%|\\/-]") and "\\" .. c or c
end

local function lua_to_regex(pat)
  local out, i, n = {}, 1, #pat
  local function class(c, in_set)
    local lower = c:lower()
    local body = CLASS[lower]
    if not body then return nil end
    if in_set then
      if c ~= lower then return nil end -- negated class inside a set: not worth it
      return body
    end
    return (c == lower and "[" or "[^") .. body .. "]"
  end
  while i <= n do
    local c = pat:sub(i, i)
    if c == "%" then
      local nx = pat:sub(i + 1, i + 1)
      if nx == "b" or nx == "f" or nx:match("%d") then return nil end
      out[#out + 1] = class(nx, false) or regex_escape(nx)
      i = i + 2
    elseif c == "[" then
      local set, j = { "[" }, i + 1
      if pat:sub(j, j) == "^" then set[#set + 1] = "^"; j = j + 1 end
      local first = true
      while j <= n do
        local d = pat:sub(j, j)
        if d == "]" and not first then break end
        if d == "%" then
          local nx = pat:sub(j + 1, j + 1)
          local cls = class(nx, true)
          if nx:match("%a") and not cls then return nil end
          set[#set + 1] = cls or ("\\" .. nx)
          j = j + 2
        else
          set[#set + 1] = (d == "\\" or d == "[" or d == "]") and "\\" .. d or d
          j = j + 1
        end
        first = false
      end
      if j > n then return nil end
      set[#set + 1] = "]"
      out[#out + 1] = table.concat(set)
      i = j + 1
    elseif c == "-" then
      out[#out + 1] = "*?"
      i = i + 1
    elseif c == "^" and i == 1 then
      out[#out + 1] = "^"; i = i + 1
    elseif c == "$" and i == n then
      out[#out + 1] = "$"; i = i + 1
    elseif c:match("[%.%*%+%?%(%)]") then
      out[#out + 1] = c; i = i + 1
    else
      out[#out + 1] = regex_escape(c); i = i + 1
    end
  end
  return table.concat(out)
end

---------------------------------------------------------------------------
-- Query rewriting
---------------------------------------------------------------------------

-- Reads a query string literal starting at the opening quote. Returns the
-- decoded text and the index just past the closing quote.
local function read_string(s, i)
  local buf, j = {}, i + 1
  while j <= #s do
    local c = s:sub(j, j)
    if c == "\\" then
      local nx = s:sub(j + 1, j + 1)
      buf[#buf + 1] = ({ n = "\n", t = "\t", r = "\r", ["0"] = "\0" })[nx] or nx
      j = j + 2
    elseif c == '"' then
      return table.concat(buf), j + 1
    else
      buf[#buf + 1] = c
      j = j + 1
    end
  end
  error("unterminated string")
end

local function encode_string(text)
  return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

-- Splits a query into its top-level patterns, dropping comments.
local function split_patterns(src)
  local patterns, cur, depth, i = {}, {}, 0, 1
  local function flush()
    local text = table.concat(cur)
    if text:match("%S") then patterns[#patterns + 1] = text end
    cur = {}
  end
  while i <= #src do
    local c = src:sub(i, i)
    if c == ";" then
      local e = src:find("\n", i, true) or #src
      i = e + 1
      cur[#cur + 1] = "\n"
    elseif c == '"' then
      if depth == 0 then flush() end
      local _, j = read_string(src, i)
      cur[#cur + 1] = src:sub(i, j - 1)
      i = j
    elseif c == "(" or c == "[" then
      if depth == 0 then flush() end
      depth = depth + 1
      cur[#cur + 1] = c
      i = i + 1
    elseif c == ")" or c == "]" then
      depth = depth - 1
      cur[#cur + 1] = c
      i = i + 1
    else
      cur[#cur + 1] = c
      i = i + 1
    end
  end
  flush()
  return patterns
end

-- Calls fn(kind, text) over a pattern's tokens: "string" (raw literal,
-- quotes included), "capture" (name without @), "predicate" (name without
-- #), or "other". Returns the concatenation of what fn returns.
local function map_tokens(pat, fn)
  local out, i = {}, 1
  while i <= #pat do
    local c = pat:sub(i, i)
    if c == '"' then
      local _, j = read_string(pat, i)
      out[#out + 1] = fn("string", pat:sub(i, j - 1))
      i = j
    elseif c == "@" then
      local name = pat:match("^[%w_%.%-]+", i + 1)
      out[#out + 1] = fn("capture", name)
      i = i + 1 + #name
    elseif c == "#" and pat:sub(i - 1, i - 1) == "(" then
      local name = pat:match("^[%w_%.%-]+[%?!]", i + 1) or pat:match("^[%w_%.%-]*", i + 1)
      out[#out + 1] = fn("predicate", name)
      i = i + 1 + #name
    else
      out[#out + 1] = fn("other", c)
      i = i + 1
    end
  end
  return table.concat(out)
end

-- Finds each "(#name ...)" form in a pattern. Returns a list of
-- { name, start, stop } with stop the index of the closing paren.
local function predicate_forms(pat)
  local forms, i = {}, 1
  while true do
    local s = pat:find("(#", i, true)
    if not s then break end
    local name = pat:match("^[%w_%.%-]+[%?!]?", s + 2)
    local depth, j = 0, s
    while j <= #pat do
      local c = pat:sub(j, j)
      if c == '"' then
        local _, k = read_string(pat, j)
        j = k
      else
        if c == "(" then depth = depth + 1 elseif c == ")" then depth = depth - 1 end
        if depth == 0 then break end
        j = j + 1
      end
    end
    forms[#forms + 1] = { name = name, start = s, stop = j }
    i = j + 1
  end
  return forms
end

local function rewrite_pattern(pat, kind, lang)
  local forms = predicate_forms(pat)
  local referenced = {}
  for _, f in ipairs(forms) do
    if UNSUPPORTED[f.name] then return nil, f.name end
    for cap in pat:sub(f.start, f.stop):gmatch("@([%w_%.%-]+)") do referenced[cap] = true end
  end

  -- Rewrite or remove predicate forms, last first so indexes stay valid.
  for k = #forms, 1, -1 do
    local f = forms[k]
    local form = pat:sub(f.start, f.stop)
    local new = form
    if STRIP[f.name] then
      new = ""
    elseif f.name == "lua-match?" or f.name == "not-lua-match?" then
      local cap, q = form:match("^%(#[%w%-]+%?%s+(@[%w_%.%-]+)%s+()")
      local text = read_string(form, q)
      local re = lua_to_regex(text)
      if not re then return nil, "lua-match? " .. text end
      new = "(#" .. (f.name == "lua-match?" and "match?" or "not-match?") .. " " .. cap
        .. " " .. encode_string(re) .. ")"
    elseif f.name == "set-lang-from-info-string!" then
      -- `(#set-lang-from-info-string! @_lang)`: rift reads the language from
      -- an @injection.language capture instead.
      local cap = form:match("@([%w_%.%-]+)")
      pat = pat:sub(1, f.start - 1) .. pat:sub(f.stop + 1)
      pat = pat:gsub("@" .. cap:gsub("%p", "%%%0") .. "([^%w_%.%-])", "@injection.language%1")
      goto continue
    end
    pat = pat:sub(1, f.start - 1) .. new .. pat:sub(f.stop + 1)
    ::continue::
  end

  if kind ~= "highlights" then return pat end

  return map_tokens(pat, function(t, text)
    if t == "string" or t == "other" or t == "predicate" then
      return t == "capture" and "@" .. text or (t == "predicate" and "#" .. text or text)
    end
    if text:sub(1, 1) == "_" then return "@" .. text end
    if NO_COLOR[text] then
      return referenced[text] and ("@_" .. text) or ""
    end
    return "@" .. rift_capture(lang, text)
  end)
end

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function write_file(path, s)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function build_query(lang, kind)
  local files = vim.treesitter.query.get_files(lang, kind)
  if #files == 0 then return nil end
  local parts, kept, dropped = {}, 0, 0
  for _, file in ipairs(files) do
    for _, pat in ipairs(split_patterns(read_file(file))) do
      local new, why = rewrite_pattern(pat, kind, lang)
      if new then
        parts[#parts + 1] = (new:gsub("^%s+", ""):gsub("%s+$", ""))
        kept = kept + 1
      else
        dropped = dropped + 1
        report.dropped[#report.dropped + 1] = lang .. "/" .. kind .. ": " .. why
      end
    end
  end
  if kind == "injections" then
    -- rift only uses `#set! injection.language` when the query also has an
    -- @injection.language capture somewhere; this pattern never matches.
    parts[#parts + 1] = '((ERROR) @injection.language (#eq? @injection.language "rift-never-matches"))'
  end
  return "; Generated by generate.lua from Neovim's queries. Do not edit.\n"
    .. table.concat(parts, "\n\n") .. "\n", kept, dropped
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local parsers = vim.api.nvim_get_runtime_file("parser/*.so", true)
local seen, langs = {}, {}
for _, path in ipairs(parsers) do
  local lang = path:gsub("\\", "/"):match("([^/]+)%.so$")
  if not seen[lang] then
    seen[lang] = true
    langs[#langs + 1] = { lang = lang, path = path }
  end
end
table.sort(langs, function(a, b) return a.lang < b.lang end)

local manifest = { "-- Generated by generate.lua. Do not edit.", "return {" }
local summary = {}
for _, l in ipairs(langs) do
  local ext = is_windows and ".dll" or ".so"
  write_file(OUT .. "/parsers/" .. l.lang .. ext, read_file(l.path))
  local hl, hk, hd = build_query(l.lang, "highlights")
  local inj, ik, id = build_query(l.lang, "injections")
  if hl then write_file(OUT .. "/queries/" .. l.lang .. "/highlights.scm", hl) end
  if inj then write_file(OUT .. "/queries/" .. l.lang .. "/injections.scm", inj) end
  local exts = {}
  for _, e in ipairs(EXTENSIONS[l.lang] or {}) do exts[#exts + 1] = string.format("%q", e) end
  manifest[#manifest + 1] = string.format(
    "  { lang = %q, highlights = %s, injections = %s, extensions = { %s } },",
    l.lang, tostring(hl ~= nil), tostring(inj ~= nil), table.concat(exts, ", "))
  summary[#summary + 1] = string.format("| %s | %s | %s | %s |", l.lang,
    hl and (hk .. (hd > 0 and " (" .. hd .. " dropped)" or "")) or "-",
    inj and (ik .. (id > 0 and " (" .. id .. " dropped)" or "")) or "-",
    table.concat(EXTENSIONS[l.lang] or { "(injected only)" }, " "))
end
manifest[#manifest + 1] = "}"
write_file(OUT .. "/manifest.lua", table.concat(manifest, "\n") .. "\n")

local r = {
  "# Generated treesitter report",
  "",
  "Generated " .. os.date("%Y-%m-%d") .. " from Neovim " .. tostring(vim.version()) .. ".",
  "",
  "| Language | Highlight patterns | Injection patterns | Extensions |",
  "|---|---|---|---|",
}
vim.list_extend(r, summary)
r[#r + 1] = ""
r[#r + 1] = "## Colors rift's theme doesn't have"
r[#r + 1] = ""
r[#r + 1] = "Neovim color -> the rift capture used instead, and which captures use it."
r[#r + 1] = ""
local keys = vim.tbl_keys(report.approx)
table.sort(keys)
for _, k in ipairs(keys) do
  table.sort(report.approx[k])
  r[#r + 1] = "- `" .. k .. "`: " .. table.concat(report.approx[k], ", ")
end
r[#r + 1] = ""
r[#r + 1] = "## Dropped patterns"
r[#r + 1] = ""
r[#r + 1] = "Patterns using predicates rift's tree-sitter can't evaluate."
r[#r + 1] = ""
for _, d in ipairs(report.dropped) do r[#r + 1] = "- " .. d end
write_file(OUT .. "/REPORT.md", table.concat(r, "\n") .. "\n")

print(("generated %d languages into %s"):format(#langs, OUT))
