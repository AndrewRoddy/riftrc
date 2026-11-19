-- Prints, for every capture name in tools/captures.txt (the ones rift
-- 0.7.7's bundled queries use), the style my Neovim draws it with:
--   capture <TAB> group Neovim resolved it to <TAB> style
-- Run from the plugin folder, with your normal Neovim config:
--   nvim --headless -i NONE -c "luafile tools/resolve.lua" -c "qa!"
-- Then update the tables in rift-nvim-colors.lua to match.
local renames = {
  conditional = "keyword.conditional", ["repeat"] = "keyword.repeat",
  field = "variable.member", method = "function.method",
  ["method.call"] = "function.method.call", parameter = "variable.parameter",
  storageclass = "keyword.modifier", ["type.qualifier"] = "keyword.modifier",
  preproc = "keyword.directive", include = "keyword.import", float = "number.float",
  escape = "string.escape", delimiter = "punctuation.delimiter",
  ["text.title"] = "markup.heading", ["text.uri"] = "markup.link.url",
  ["text.literal"] = "markup.raw", ["text.reference"] = "markup.link",
  ["string.special.regex"] = "string.regexp", ["comment.documentation"] = "comment.documentation",
  embedded = "none",
}
local function style(name)
  while name do
    if vim.fn.hlexists("@" .. name) == 1 then
      local hl = vim.api.nvim_get_hl(0, { name = "@" .. name, link = false })
      if next(hl) then return hl, name end
    end
    name = name:match("^(.*)%.[^.]+$")
  end
end
local out = {}
for cap in io.lines("tools/captures.txt") do
  local hl, from = style(renames[cap] or cap)
  local parts = {}
  if hl then
    if hl.fg then parts[#parts + 1] = string.format("fg=#%06x", hl.fg) end
    if hl.bg then parts[#parts + 1] = string.format("bg=#%06x", hl.bg) end
    for _, a in ipairs({ "bold", "italic", "underline", "strikethrough" }) do
      if hl[a] then parts[#parts + 1] = a end
    end
  end
  out[#out + 1] = cap .. "\t" .. (from or "-") .. "\t" .. table.concat(parts, " ")
end
io.stdout:write(table.concat(out, "\n") .. "\n")
