# rift-jumplist

Neovim's jump list for rift, which has none. `<C-o>` goes back to where the
cursor was before a jump, and `<C-i>` goes forward again.

| Key / command | Does |
|---|---|
| `<C-o>` | Back to the previous jump position |
| `<C-i>` / `<Tab>` | Forward to the next one (terminals send `<Tab>` for `<C-i>`) |
| `:Jumps` | Show the list (`>` marks where you are in it) |

It works like Neovim's: going back from the newest position first saves it
so `<C-i>` can return; a new jump from the middle of the list goes on the
end; each line is in the list once; and jumps into other buffers switch
back to them. Checked against Neovim 0.11 with the same keys (see Tests).

## What counts as a jump

rift doesn't tell plugins which key moved the cursor. So a jump here is
any move of 2 or more lines at once in Normal or Visual mode, or a move into
another buffer: `G`, `gg`, `/`, `n`, `%`, `{`, `}`, `gd`, `:e` and so on,
whenever they move 2 or more lines. Moves while typing in Insert mode never
count.

## Limitations

- Some moves count that Neovim doesn't: `5j`, `<C-d>`, `<C-f>`, and an
  undo that moves the cursor far.
- rift doesn't send a cursor event for some moves (`G`, `gg`, searches,
  `L`, `<C-d>`). The plugin notices them at the next key that moves the
  cursor, the next edit or mode change, `<C-o>` / `<C-i>`, or when the cursor
  rests (CursorHold). The one case it can miss is two of those moves in
  a row with nothing in between (`G` straight into `gg`). Then the
  position between them is skipped.
- Positions don't shift when lines are added or deleted above them. A
  position past the end of the buffer goes to the last line.
- No count (`3<C-o>`): rift drops counts before mapped keys.
- `rift.switch_buf` doesn't change what the window shows (rift 0.7.7), so
  other buffers are reached with `:buffer N`.

## Options

```lua
require("rift-jumplist").setup({
  back = "<C-o>",                -- false to disable
  forward = { "<C-i>", "<Tab>" }, -- false to disable
  min_lines = 2,                 -- a move of at least this many lines is a jump
  max = 100,                     -- positions kept
})
```

## Tests

`bash tests/jumplist.sh` types keys into headless rift with `rift-replay`
(it comes with rift) and checks the cursor. The expected positions are
what Neovim does with the same keys.

## Install

Copy `rift-jumplist.lua` into rift's plugins directory
(`%APPDATA%\rift\plugins` on Windows, `~/.config/rift/plugins` elsewhere).
It sets itself up with the defaults.

Tested with rift 0.7.7.
