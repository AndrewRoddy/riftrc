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

-- Plugins: each one is standalone, in plugins/<name>/<name>.lua (see
-- plugins/<name>/README.md), so it can be released on its own. Here they're
-- require()d, which lets this config pass options to setup().
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("(.*)/")
package.path = package.path .. ";" .. here .. "/plugins/?/?.lua"

require("rift-indent").setup()    -- `>>` / `<<` line shifting
require("rift-comment").setup()   -- Comment.nvim
require("rift-closetag").setup()  -- vim-closetag
require("rift-conform").setup()   -- conform.nvim
require("rift-splunk").setup()    -- splunk-syntax.nvim
require("rift-open-line").setup() -- `o` keeps the line's indent
require("rift-join").setup()      -- `J` / `gJ` join lines like Neovim
require("rift-clipboard").setup() -- clipboard=unnamedplus: yanks go to the system clipboard
