# rift-indent

Neovim-style `>>` and `<<` for rift, which has no line shifting of its own.

| Key / command | Effect |
|---|---|
| `>>` | Shift the current line one shiftwidth right |
| `<<` | Shift the current line one shiftwidth left |
| `:Indent [n]` | Shift `n` lines right, starting at the cursor (default 1) |
| `:Dedent [n]` | Shift `n` lines left, starting at the cursor (default 1) |

Checked against Neovim 0.11 on the same inputs: the text and the cursor
position come out the same. Shiftwidth follows the buffer's `tab_width`. The
new indent is rebuilt from its width, so mixed tabs and spaces normalize to
`expandtab` / `tab_width`. Empty lines stay empty. Like Neovim's default
`nostartofline`, the cursor keeps its screen column. Terminal, explorer and
read-only buffers are skipped.

## Options

```lua
{
  shiftwidth = nil,  -- nil follows the buffer's tab_width
  mappings = true,
  reselect = true,   -- keep the selection after visual > / < (when rift supports it)
}
```

## Limitations

- No count (`3>>`): rift drops counts before mapped keys. `:Indent 3` does it.
- No `>` / `<` as operators (`>j`, `>ap`) and no `.` repeat.
- No visual `>` / `<`: rift plugins can't map visual-mode keys or read the
  selection. The code is there for when rift adds `rift.get_selection()`.
- The dedent key is written `"<lt><lt>"`: rift reads a bare `<` as the start
  of a `<...>` key name and silently drops mappings it can't parse.

## Install

`rift-indent.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-indent/?.lua"
require("rift-indent").setup({ shiftwidth = 2 })
```

Tested with rift 0.7.5.
