
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

require("riftrc.plugins.indent").setup()    -- `>>` / `<<` line shifting

-- Ports of my Neovim plugins (see README.md)
require("riftrc.plugins.comment").setup()   -- Comment.nvim
require("riftrc.plugins.closetag").setup()  -- vim-closetag
require("riftrc.plugins.conform").setup()   -- conform.nvim
require("riftrc.plugins.splunk").setup()    -- splunk-syntax.nvim
require("riftrc.plugins.open_line").setup() -- `o` keeps the line's indent

