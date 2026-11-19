-- rift-nvim-colors: rift's syntax colors set to what my Neovim draws.
--
-- My Neovim config (lua/nvimrc/init.lua, `code_colors`) gives eight colors
-- to highlight groups. rift's tree-sitter highlighting uses the same kind of
-- capture names (`keyword`, `function.call`, ...), so each one rift's queries
-- use is set to the color Neovim resolves for it: from my config where it
-- sets one, otherwise from Neovim's default links. tools/resolve.lua asks
-- Neovim for that table again (see README).
--
-- Some of rift's queries use older capture names (`conditional`, `field`,
-- `method`, ...); they get the color of the name Neovim's queries use now
-- (`keyword.conditional`, `variable.member`, `function.method`, ...).
local MODULE = ...
local M = {}

local NORMAL = "#EBDBB2"

-- Laid out like `code_colors` in my Neovim config: color -> rift captures.
M.colors = {
  ["#ff922f"] = { -- Keyword, Statement, PreProc
    "keyword", "keyword.conditional", "keyword.coroutine", "keyword.debug",
    "keyword.exception", "keyword.function", "keyword.import", "keyword.modifier",
    "keyword.operator", "keyword.repeat", "keyword.return", "keyword.type",
    "conditional", "repeat", "storageclass", "type.qualifier", "preproc",
    "include", "import", "label", "attribute",
  },
  ["#8ec07c"] = { -- Function
    "function", "function.builtin", "function.call", "function.macro",
    "function.method", "function.method.builtin", "function.special",
    "method", "method.call",
  },
  ["#fabd2f"] = { "type", "type.builtin" }, -- Type
  ["#b8bb26"] = { "string", "character" }, -- String, Character
  ["#d3869b"] = { -- Number, Boolean, Constant
    "number", "number.float", "float", "boolean", "constant",
  },
  ["#83a598"] = { -- Special, @module, @constant.builtin, @variable.builtin
    "module", "module.builtin", "namespace", "constant.builtin",
    "variable.builtin", "builtin", "constructor", "escape", "string.escape",
    "string.special", "string.special.key", "string.special.regex",
    "string.special.symbol", "punctuation.special", "tag", "tag.delimiter",
    "tag.error", "text.literal",
  },
  ["#928374"] = { "comment", "comment.documentation" }, -- Comment
  [NORMAL] = { -- Identifier, Operator, Delimiter, @variable, @punctuation
    "variable", "variable.member", "variable.parameter", "field", "parameter",
    "property", "property.definition", "operator", "delimiter", "punctuation",
    "punctuation.bracket", "punctuation.delimiter", "none", "embedded", "spell",
  },
}

-- Neovim's defaults for the Markdown ones (Title, Underlined).
M.styles = {
  ["text.title"] = { fg = "#e0e2ea", bold = true },
  ["text.reference"] = { fg = NORMAL, underline = true },
  ["text.uri"] = { fg = NORMAL, underline = true },
}

function M.apply()
  for color, groups in pairs(M.colors) do
    for _, group in ipairs(groups) do
      rift.highlight.set(group, { fg = color })
    end
  end
  for group, style in pairs(M.styles) do
    rift.highlight.set(group, style)
  end
end

-- opts.styles overrides single groups, after the colors above:
--   styles = { comment = { fg = "#928374", italic = true } }
function M.setup(opts)
  for group, style in pairs((opts or {}).styles or {}) do M.styles[group] = style end
  M.apply()
  rift.register_command("NvimColors", M.apply, "Set the syntax colors to my Neovim's again")
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
