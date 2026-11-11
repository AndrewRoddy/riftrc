# rift-comment

Comment.nvim for rift: toggle line and block comments.

| Key / command | Effect |
|---|---|
| `gcc` / `gbc` | Toggle a line / block comment on the current line |
| `gcj` `gck`, `gc{1-9}j` `gc{1-9}k` | Toggle lines from the cursor down / up |
| `gcip` `gcap` `gcgg` `gcG` | Toggle the paragraph / to the top / to the bottom |
| `gco` `gcO` `gcA` | Start a comment below / above / at the end of the line |
| `:CommentToggle [n]` | Toggle `n` lines from the cursor |
| `:CommentBlockToggle [n]` | Block comment around `n` lines |

All lines are commented at the shallowest indent, blank lines are skipped,
and a range that is fully commented is uncommented. The comment string comes
from rift's filetype, falling back to the file extension (so `.razor` uses
`@* *@`). Undo takes one `u`.

## Options

```lua
{
  padding = true,   -- a space between the comment marker and the text
  mappings = true,  -- set up the keys above
  commentstrings = { ext = { "//%s", "/*%s*/" } },  -- add or override: { line, block }
}
```

## Limitations

- No `gc{motion}` beyond the motions above, and no count before the key
  (`3gcc`): rift gives plugins no operator-pending hook and drops counts
  before mapped keys. `:CommentToggle 3` does `3gcc`.
- No visual `gc` / `gb`: rift plugins can't map visual-mode keys or read
  the selection. The visual code is there for when rift adds it.
- `.` doesn't repeat a toggle.

## Install

`rift-comment.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-comment/?.lua"
require("rift-comment").setup({ padding = true })
```

Tested with rift 0.7.5.
