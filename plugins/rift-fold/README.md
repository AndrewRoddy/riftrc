# rift-fold

Indent-based code folding in rift, with Vim's keys.

| Key | Command | Does |
|---|---|---|
| `zc` | `:FoldClose` | Close the block the cursor is on |
| `zo` | `:FoldOpen` | Open the closed fold on the cursor line |
| `za` | `:FoldToggle` | Open it if it's closed, close it otherwise |
| `zR` | `:FoldOpenAll` | Open every fold |
| `zM` | `:FoldCloseAll` | Close every top-level block |

A block is found like Vim's `foldmethod=indent`: the lines under a line that
are indented deeper than it. On a line that isn't followed by deeper lines,
`zc` closes the block around the cursor. A closing `}` / `)` / `]` / `end` /
`</tag>` line at the block's indent is folded too, so a function folds to
its first line:

```
function a() {  ··· 5 lines
```

## How it works, and what that means

rift can't hide lines, so a closed fold **cuts its lines out of the buffer**
and keeps them in the plugin. Opening the fold puts them back. So:

- **Saving while folded is safe.** After every save the plugin writes the
  hidden lines back into the file, so the file on disk always has the full
  text (LF and CRLF files, with or without a final newline).
- Closing or opening a fold is an edit: the buffer shows as modified and
  `:q` will want you to save first. `:wq` is fine.
- Each fold is one undo step. `u` right after `zc` brings the lines back and
  forgets the fold.
- Closing a block that contains closed folds merges them, so opening it
  shows everything open.
- If you delete a fold's first line, the hidden lines stay where they were
  and come back on `zo`/`zR`, or on save.
- Folds last until rift closes the buffer; they aren't remembered between
  sessions.
- Search, `:s` and other plugins only see what's in the buffer, so they
  don't see inside closed folds. `rift-conform` won't format a buffer with
  closed folds (it warns and skips); `zR` first.

## Options

```lua
require("rift-fold").setup({
  text = "  ··· %d lines",                   -- after a closed fold; %d = line count
  style = { fg = "#928374", italic = true }, -- colour of that text
  keys = true,                               -- false: commands only, no z maps
})
```

## Install

`rift-fold.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-fold/?.lua"
require("rift-fold").setup()
```

rift-conform only knows to skip folded buffers when rift-fold is loaded
with `require`.

Tested with rift 0.7.5.
