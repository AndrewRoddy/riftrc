# rift-term-scroll

Scroll a terminal's history from terminal-normal mode, the way Neovim does.

In rift, leaving terminal mode (`<C-\>`, or whatever you map to
`terminal:exit`) doesn't turn the scrollback into a buffer like Neovim does.
The buffer is only the visible screen, so `k` stops at the top row. Older
output is reachable only through rift's scroll actions, and rift binds just
`<C-u>` / `<C-d>` to them.

In terminal-normal mode this plugin adds:

| Key | Does |
|---|---|
| `k` / `<Up>` | Move up; on the top row, scroll the history up 5 lines |
| `j` / `<Down>` | Move down; on the bottom row, scroll back down 5 lines |
| `<C-y>` / `<C-e>` | Scroll up / down 5 lines |
| `<C-b>` / `<C-f>` | Scroll up / down 20 lines |
| `<PageUp>` / `<PageDown>` | Scroll up / down 20 lines |
| `gg` / `G` | Scroll to the top of the history / back to the bottom |

**Scroll mode:** press `<A-a>` again in terminal-normal mode (so `Alt+a`
twice from the terminal) and `k` / `j` / arrows scroll the history 5 lines
at a time instead of moving the cursor. `<A-a>` again turns it off; `i`
also leaves it.

rift's own `<C-u>` / `<C-d>` (10 lines) still work, in terminal mode too.
Press `i` and type anything to jump back to the bottom.

rift only has 5- and 20-line scroll steps and no "top of history" action,
so `gg` / `G` page 500 times (enough for rift's 10,000-line history). rift
doesn't capture the mouse wheel.

## Options

```lua
require("rift-term-scroll").setup({
  edge_scroll = true,               -- k/j scroll at the top/bottom row
  scroll_key = "<A-a>",             -- toggles scroll mode; false to disable
  jump = true,                      -- gg / G; false to disable
  jump_steps = 500,                 -- 20-line pages gg / G scroll
  keys = {
    ["<C-b>"] = false,              -- drop a default map
    ["<A-k>"] = "terminal:scroll_up",
  },
})
```

## Install

`rift-term-scroll.lua` is the whole plugin and has no dependencies. Copy it
into rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-term-scroll/?.lua"
require("rift-term-scroll").setup()
```

Tested with rift 0.7.5.
