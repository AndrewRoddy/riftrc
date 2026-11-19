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

-- Plugins are loaded by riftpm (github.com/Monster0506/riftpm). The list is
-- in plugins.lua. riftpm itself goes in rift's plugins folder, next to this
-- config, and is cloned there the first time if it's missing.
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("(.*)/")
local riftpm = here:match("(.*)/") .. "/riftpm"
local function have_riftpm()
  local f = io.open(riftpm .. "/riftpm.lua", "r")
  if f then f:close() end
  return f ~= nil
end
if not have_riftpm() then
  local git = io.popen('git clone --depth=1 https://github.com/Monster0506/riftpm "'
    .. riftpm .. '" 2>&1')
  if git then git:read("a") git:close() end
end
if have_riftpm() then
  package.path = package.path .. ";" .. riftpm .. "/?.lua"
  require("riftpm").setup({ plugins = dofile(here .. "/plugins.lua") })
else
  rift.notify("error", "Couldn't install riftpm, so no plugins are loaded. Clone "
    .. "github.com/Monster0506/riftpm into " .. riftpm)
end
