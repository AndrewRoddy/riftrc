# rift-clipboard

Yanks go to the system clipboard in rift, like Neovim's `clipboard=unnamedplus`.

These yanks also go to the system clipboard (clip.exe on Windows, pbcopy,
wl-copy or xclip elsewhere):

- Visual mode: `v`, `V` and `<C-v>` selections yanked with `y`
- `yy` `Y` `y_` `y$` `y0` `y^` `yl` `yh` `yw` `yW` `ye` `yE` `yb` `yB`
- `yj` `yk` `ygg` `yG` `y}` `y{` `y%`
- `yf` `yt` `yF` `yT` followed by a character
- `yiw` `yaw` `yiW` `yaW` `yip` `yap`
- quote and bracket objects: `yi"` `ya"` `yi'` `` yi` `` `yi(` `yib` `yi{` `yiB` `yi[` `yi<` and the `a` forms

Text with non-ASCII characters and emoji comes through intact.

## How it works, and what it costs

rift never writes the system clipboard, and plugins can't see its yanks,
run its yank operator, or map Visual-mode keys.

**Normal mode.** A mapping like `yy` can't fire while `y` is rift's operator:
rift runs an operator key immediately. So this plugin maps Normal-mode `y`
itself and implements the yanks above in Lua.

Because these yanks never reach rift's register, `p` / `P` paste them while
they're the newest thing yanked. After Visual mode, `dd`, `x`, `D`,
`d{motion}` or `c{motion}`, rift's register may hold something newer, so
`p` / `P` go back to rift's own. `u` and `<C-r>` are mapped so undoing a
paste doesn't count as a delete.

**Visual mode** keeps rift's own `y`. The plugin notes where the selection
started and where the cursor was when Visual mode ended, then checks the
cursor a moment later: rift's `y` moves it to the start of the selection,
`Esc` leaves it where it was. If it moved there, the selection is copied.
`d`, `c` and `x` change the text and are ignored.

Checking "a moment later" relies on CursorHold, the only thing that runs
plugin code while rift is idle. When Visual mode ends, the plugin sets the
CursorHold delay to one poll (about 16 ms) and then puts it back to
`cursor_hold_ms`. If CursorHold isn't armed (no cursor movement since it
last fired), the plugin nudges the cursor one step to arm it. A real `y`
puts the cursor back at the selection's start anyway, and after `Esc` the
nudge is undone.

## Options

```lua
{
  report = 2,            -- show "N lines yanked" for yanks of more lines than this
  visual = true,         -- copy Visual-mode yanks
  cursor_hold_ms = 400,  -- CursorHold delay to restore (rift's default)
}
```

## Limitations

- Any `y{motion}` not listed above does nothing in Normal mode.
- No counts (`3yy`, `2yw`): rift drops counts before plugin keymaps. Visual
  mode works instead (`V2jy`).
- A selection made backwards (cursor at its start) and left with `Esc` is
  copied too: it looks exactly like a `y` from outside.
- Swapping the selection's ends with `o` in Visual mode confuses it.
- After `Esc` from Visual mode the cursor may sit one step off for a frame
  (the nudge) before it's put back.
- No `.` repeat, and deletes don't reach the system clipboard.

## Install

`rift-clipboard.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-clipboard/?.lua"
require("rift-clipboard").setup({ report = 5 })
```

Tested with rift 0.7.5.
