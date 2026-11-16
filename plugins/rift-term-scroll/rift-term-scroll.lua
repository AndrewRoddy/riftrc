-- Scroll a terminal's scrollback from terminal-normal mode, like Neovim.
--
-- In Neovim, leaving terminal mode turns the whole scrollback into a buffer,
-- so `k`, `<C-b>`, `<C-y>` and friends walk back through history. In rift the
-- terminal buffer is only the visible screen; history is a separate "view
-- offset" moved by the terminal:scroll_* actions (rift binds only <C-u>/<C-d>
-- to it). So `k` stops at the top row and nothing older is reachable.
--
-- This maps the usual Vim scroll keys in terminal-normal mode ("tn") to those
-- actions, and makes `k` / `j` scroll when the cursor is on the top / bottom
-- row. Nothing changes in file buffers or in terminal (insert) mode.
--
-- Pressing `scroll_key` (Alt+a by default, the same key that leaves terminal
-- mode) again in terminal-normal mode toggles a scroll mode: `k`/`j` scroll
-- the history instead of moving the cursor. Press it again, or `i`, to leave.
--
-- rift only exposes fixed scroll steps: 5 lines (terminal:scroll_up/down) and
-- 20 lines (terminal:scroll_page_up/down). Typing in terminal mode jumps back
-- to the bottom.
local M = {}
local MODULE = ...

local defaults = {
  -- Make `k` on the top row / `j` on the bottom row scroll the history.
  edge_scroll = true,
  -- Key that toggles scroll mode in terminal-normal mode. false to disable.
  scroll_key = "<A-a>",
  -- Extra terminal-normal maps: key -> action. Set a key to false to drop it.
  keys = {
    ["<C-y>"] = "terminal:scroll_up",
    ["<C-e>"] = "terminal:scroll_down",
    ["<C-b>"] = "terminal:scroll_page_up",
    ["<C-f>"] = "terminal:scroll_page_down",
    ["<PageUp>"] = "terminal:scroll_page_up",
    ["<PageDown>"] = "terminal:scroll_page_down",
  },
}

-- Keymaps run the command through `:lua`: rift refreshes what plugins read
-- (cursor, line count) right before `:lua`, but not before a mapped
-- `editor:run:Command`, which would see the cursor from before the last
-- motion. _rift_commands is rift's table of registered plugin commands.
local function map(mode, keys, name)
  rift.map(mode, keys, string.format("editor:run:lua _rift_commands[%q].fn({})", name))
end

-- Scroll mode: k/j scroll instead of moving. rift has no custom modes, so
-- it's a silent flag the k/j commands check, cleared when leaving normal
-- mode (`i`).
local scrolling = false
local edge_scroll = true

function M.toggle()
  if rift.buf_kind() ~= "terminal" then return end
  scrolling = not scrolling
end

-- Scrolling rebuilds the terminal buffer from the screen and resets the
-- cursor, so put it back on the edge row afterwards: holding `k` keeps
-- scrolling instead of the cursor jumping around. Mutations apply in order.
local function edge_move(dir)
  if rift.buf_kind() ~= "terminal" then
    rift.exec_action(dir < 0 and "editor:move:up" or "editor:move:down")
    return
  end
  if scrolling then
    rift.exec_action(dir < 0 and "terminal:scroll_up" or "terminal:scroll_down")
    return
  end
  local row, col = rift.get_cursor()
  local last = rift.get_line_count()
  if not edge_scroll then
    rift.exec_action(dir < 0 and "editor:move:up" or "editor:move:down")
  elseif dir < 0 and row <= 1 then
    rift.exec_action("terminal:scroll_up")
    rift.set_cursor(1, col)
  elseif dir > 0 and row >= last then
    rift.exec_action("terminal:scroll_down")
    rift.set_cursor(last, col)
  else
    rift.exec_action(dir < 0 and "editor:move:up" or "editor:move:down")
  end
end

function M.up() edge_move(-1) end
function M.down() edge_move(1) end

-- rift has no "scroll to top/bottom" action, so page enough times to cross
-- the whole history (rift keeps alacritty's default of 10,000 lines; 20 per
-- page). Scrolling past either end is clamped, so extra steps are harmless.
local jump_steps = 500

local function jump(dir)
  if rift.buf_kind() ~= "terminal" then return end
  local action = dir < 0 and "terminal:scroll_page_up" or "terminal:scroll_page_down"
  for _ = 1, jump_steps do rift.exec_action(action) end
  local _, col = rift.get_cursor()
  rift.set_cursor(dir < 0 and 1 or rift.get_line_count(), col)
end

function M.top() jump(-1) end
function M.bottom() jump(1) end

function M.setup(opts)
  opts = opts or {}
  local keys = {}
  for k, v in pairs(defaults.keys) do keys[k] = v end
  for k, v in pairs(opts.keys or {}) do keys[k] = v end
  local edge = opts.edge_scroll
  if edge == nil then edge = defaults.edge_scroll end
  edge_scroll = edge

  for k, action in pairs(keys) do
    if action then rift.map("tn", k, action) end
  end

  if opts.jump_steps then jump_steps = opts.jump_steps end
  if opts.jump ~= false then
    rift.register_command("TermScrollTop", M.top, "Scroll to the top of the terminal history")
    rift.register_command("TermScrollBottom", M.bottom, "Scroll to the bottom of the terminal")
    map("tn", "gg", "TermScrollTop")
    map("tn", "G", "TermScrollBottom")
  end

  local scroll_key = opts.scroll_key
  if scroll_key == nil then scroll_key = defaults.scroll_key end

  if edge or scroll_key then
    rift.register_command("TermScrollUp", M.up,
      "Move up; scroll the terminal history on the top row")
    rift.register_command("TermScrollDown", M.down,
      "Move down; scroll the terminal history on the bottom row")
    map("tn", "k", "TermScrollUp")
    map("tn", "j", "TermScrollDown")
    map("tn", "<Up>", "TermScrollUp")
    map("tn", "<Down>", "TermScrollDown")
  end

  if scroll_key then
    rift.register_command("TermScrollMode", M.toggle,
      "Toggle terminal scroll mode (k/j scroll the history)")
    map("tn", scroll_key, "TermScrollMode")
    rift.on("ModeChanged", function(ev)
      if ev.to ~= "normal" then scrolling = false end
    end)
    rift.on("BufLeave", function() scrolling = false end)
  end
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
