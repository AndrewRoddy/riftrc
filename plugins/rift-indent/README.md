# rift-indent

Neovim-style `>>` and `<<` for rift, which has no line shifting of its own.

| Key / command | Effect |
|---|---|
| `>>` | Shift the current line one shiftwidth right |
| `<<` | Shift the current line one shiftwidth left |
| `>` (Visual) | Shift the selected lines right and keep the selection (Neovim's `>gv`) |
| `<` (Visual) | Shift the selected lines left and keep the selection (`<gv`) |
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
- Visual `>` / `<`: rift plugins can't map Visual-mode keys, read the
  selection or re-enter Visual mode. This relies on Visual falling back to
  Normal-mode keys, remembers where Visual mode started (`ModeChanged`), and
  rewrites the lines without leaving Visual. rift's selection anchor is a
  fixed character offset, so when the shift would move it off its line
  (selecting upward with `Vk`, or `<` with the anchor past the new line end)
  the lines are still shifted but Visual mode ends. After `o` or `gv` the
  remembered start is wrong.
- A shift in Visual is two undo steps inside rift; `u` / `<C-r>` are
  wrapped (after rift-clipboard's, which they call) to take both at once.
- `>` / `<` are mapped on their own so Visual doesn't wait for a second key;
  in Normal, a second `>` / `<` on the same spot does `>>` / `<<`.
- The dedent key is written `"<lt><lt>"`: rift reads a bare `<` as the start
  of a `<...>` key name and silently drops mappings it can't parse.
- Plugins can't see rift's remembered column (curswant). After `j` / `k`
  through shorter lines, Neovim puts the cursor back at the remembered
  column after a shift; here it stays where rift shows it.

## Tests

`tests/visual_indent.py` types the same keys into headless rift
(via `rift-replay`) and into `nvim --embed`, then compares the text, cursor
and mode after each case. It needs `nvim` on PATH and `pip install msgpack`.

```sh
python visual_indent.py                    # hand-written cases + a short fuzz
python visual_indent.py --fuzz 800 --seed 11 --jobs 8
python visual_indent.py -k "V j >" -v      # cases whose name contains the text
python visual_indent.py --wide             # fuzz with w / 0 moves too
```

`--speed slow|fast|both` types keys one at a time or all at once (`>>` / `<<`
pressed fast was where the "lines yanked" bug showed up). The fuzz never types
`x` on an empty line: rift's `x` deletes the line there and Neovim's does
nothing, which is rift core, not this plugin.

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
