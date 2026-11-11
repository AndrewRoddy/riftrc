# rift-join

`J` and `gJ` for rift, joining lines exactly like Neovim. rift has no line join.

| Key / command | Effect |
|---|---|
| `J` | Join the next line onto this one with one space |
| `gJ` | Join without adding or removing whitespace |
| `:Join [n]` | `J` on `n` lines (default 2) |
| `:JoinRaw [n]` | `gJ` on `n` lines (default 2) |

Like Neovim:

- The joined line's leading whitespace becomes one space, except when it is
  empty or starts with `)`, or when this line is empty or ends in a space or
  tab. One space after `.` too (`nojoinspaces`).
- The comment leader of the joined line is removed when the line it joins
  onto has a comment in it: `-- a` + `-- b` gives `-- a b`, and
  `x = 1 -- a` + `-- b` gives `x = 1 -- a b`. The ` * ` of `/* */` middle
  lines goes too (`formatoptions` j, Neovim's default).
- The cursor lands on the join point. On the last line nothing happens.
- Undo takes one `u`.

Checked against Neovim 0.11 on 31 cases (text and cursor position), covering
Lua, Python, C and JavaScript comments.

No options. Comment leaders are known for about 60 filetypes and extensions
(`//`, `--`, `#`, `;`, `"`, `%`, `/* */`, ...).

## Limitations

- `3J` joins two lines: rift drops counts before mapped keys. Use `:Join 3`.
- No visual `J`: rift plugins can't map visual-mode keys.

## Install

`rift-join.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-join/?.lua"
require("rift-join").setup()
```

Tested with rift 0.7.5.
