-- Unmaps just incase (probably does nothing)
rift.unmap("i", "<A-a>")

-- Maps Alt+a to take me from insert to normal mode
rift.map("i", "<A-a>", "mode:normal")

-- Maps Alt+a to take me from terminal insert to terminal normal
rift.map("t", "<A-a>", "terminal:exit")

-- No glide animation
rift.exec_action("editor:run:set cursorspeed=1.0")

-- noice.nvim: the command line is already a centered popup in rift; this
-- makes it a fixed 60 columns wide with a box border, like my noice setup.
rift.set_option("command_line.width_ratio", "0.0")
rift.set_option("command_line.min_width", "60")
rift.set_option("command_line.borderstyle", "unicode")

-- Same background and foreground as my Neovim (#282820 / #EBDBB2).
rift.set_option("appearance.theme", "gruvbox")

-- Plugins: each one is standalone, in plugins/<name>/<name>.lua (see
-- plugins/<name>/README.md), so it can be released on its own. Here they're
-- require()d, which lets this config pass options to setup().
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("(.*)/")
package.path = package.path .. ";" .. here .. "/plugins/?/?.lua"

require("rift-indent").setup()    -- `>>` / `<<` line shifting
require("rift-comment").setup()   -- Comment.nvim
require("rift-closetag").setup()  -- vim-closetag
require("rift-conform").setup()   -- conform.nvim
-- Disabled: syntax highlighting exactly like Neovim's (asks a headless
-- nvim). Uncomment to turn it back on, and drop rift-splunk below, which it
-- covers.
-- require("rift-nvim-syntax").setup({
--   -- What lua/nvimrc/treesitter.lua does besides queries: Splunk dashboards
--   -- are XML with SPL injected, gated on the splunkxml filetype.
--   nvim_init = [[
--     vim.treesitter.language.register("xml", "splunkxml")
--     vim.treesitter.query.add_predicate("splunkxml?", function(_, _, source)
--       return type(source) == "number" and vim.bo[source].filetype == "splunkxml"
--     end, { force = true })
--   ]],
-- })
require("rift-splunk").setup()    -- Splunk (SPL) highlighting
require("rift-open-line").setup() -- `o` keeps the line's indent
require("rift-join").setup()      -- `J` / `gJ` join lines like Neovim
require("rift-clipboard").setup() -- clipboard=unnamedplus: yanks go to the system clipboard
