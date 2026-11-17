-- Unmaps just incase (probably does nothing)
rift.unmap("i", "<A-a>")

-- Maps Alt+a to take me from insert to normal mode
rift.map("i", "<A-a>", "mode:normal")

-- Maps Alt+a to take me from terminal insert to terminal normal
rift.map("t", "<A-a>", "terminal:exit")

-- Esc / Alt+a leave Visual (v, V, Ctrl+V) in one press, like Neovim. rift's
-- first Esc only leaves Visual and keeps the selection highlighted as a
-- "banked" region; the second mode:normal clears that. Visual mode falls
-- back to Normal-mode keys, so mapping them in "n" covers Visual too.
rift.register_command("ExitVisual", function()
  -- Tell rift-clipboard this isn't a Visual `y` (it can't tell them apart).
  local not_yank = _rift_commands.ClipboardNotYank
  if not_yank then not_yank.fn({}) end
  rift.exec_action("mode:normal")
  rift.exec_action("mode:normal")
end, "Leave Visual mode and clear the selection")
rift.map("n", "<Esc>", "editor:run:lua _rift_commands.ExitVisual.fn({})")
rift.map("n", "<A-a>", "editor:run:lua _rift_commands.ExitVisual.fn({})")

-- No glide animation
rift.exec_action("editor:run:set cursorspeed=1.0")

-- noice.nvim: the command line is already a centered popup in rift; this
-- makes it a fixed 60 columns wide with a box border, like my noice setup.
rift.set_option("command_line.width_ratio", "0.0")
rift.set_option("command_line.min_width", "60")
rift.set_option("command_line.borderstyle", "unicode")
rift.set_option("quitonq", "off")

-- Same background and foreground as my Neovim (#282820 / #EBDBB2).
rift.set_option("appearance.theme", "gruvbox")

-- Plugins: each one is standalone, in plugins/<name>/<name>.lua (see
-- plugins/<name>/README.md), so it can be released on its own. Here they're
-- require()d, which lets this config pass options to setup().
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("(.*)/")
package.path = package.path .. ";" .. here .. "/plugins/?/?.lua"

require("rift-indent").setup()          -- `>>` / `<<` line shifting
require("rift-comment").setup()         -- Comment.nvim
require("rift-closetag").setup()        -- vim-closetag
require("rift-conform").setup()         -- conform.nvim
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
require("rift-splunk").setup()          -- Splunk (SPL) highlighting
require("rift-open-line").setup()       -- `o` keeps the line's indent
require("rift-join").setup()            -- `J` / `gJ` join lines like Neovim
require("rift-clipboard").setup()       -- clipboard=unnamedplus: yanks go to the system clipboard
require("rift-fold").setup()            -- zc/zo/za/zR/zM indent folding
require("rift-term-scroll").setup()     -- scroll terminal history with k/j/<C-b>/<C-f> after Alt+a
require("rift-increment").setup()       -- <C-a> / <C-x> add to / subtract from a number
-- Off for now: needs rift.term_send, which released rift doesn't have yet.
-- require("rift-rerun").setup()        -- Alt+r / Alt+Shift+r re-run the last / second-last terminal command
require("rift-insert-nonblank").setup() -- `I` inserts at the first non-blank, like Neovim
require("rift-jumplist").setup()        -- <C-o> / <C-i> jump list

-- riftquire (vimquire for rift): :Search, :SearchSources, ... Lives in its own
-- repo. Skipped if the folder isn't there, since an error here would stop
-- rift from starting.
local riftquire = "C:/Coding/riftquire"
local probe = io.open(riftquire .. "/lua/riftquire/init.lua", "r")
if probe then
  probe:close()
  package.path = package.path .. ";" .. riftquire .. "/lua/?.lua;" .. riftquire .. "/lua/?/init.lua"
  require("riftquire").setup()
end
