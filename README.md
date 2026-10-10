# riftrc

My config for [rift](https://github.com/monster0506/rift), a vim-like modal
terminal text editor. `.riftrc` files aren't supported yet, so this is a Lua
plugin instead.

## Layout

```
riftrc/
  init.lua          -- personal config (keymaps, settings), then loads plugins/
  plugins/
    indent.lua      -- `>>` / `<<` line shifting
    comment.lua     -- Comment.nvim
    closetag.lua    -- vim-closetag
    conform.lua     -- conform.nvim (format on save)
    splunk.lua      -- splunk-syntax.nvim
    open_line.lua   -- `o` keeps the current line's indentation
```

`init.lua` holds settings that are just a line of config. Anything with real
behaviour gets its own module under `plugins/`, exposing a `setup(opts)` that
`init.lua` calls. Each one is independent -- delete the `require` line and the
feature is gone.

## Installing

`%APPDATA%/rift/plugins` (or `~/.config/rift/plugins`) only loads top-level
`.lua` files, and its directory isn't on `package.path`, so a one-line loader
sits next to this repo:

```lua
-- plugins/load.lua
local dir = _rift_current_plugin_file:match("(.*)/[^/]+$")
package.path = package.path .. ';' .. dir .. '/?.lua;' .. dir .. '/?/init.lua'

require("riftrc")
```

## plugins/indent.lua

Neovim-style line shifting, which rift has no built-in equivalent for.

| Key / command | Effect |
|---|---|
| `>>` | Shift the current line one shiftwidth right |
| `<<` | Shift the current line one shiftwidth left |
| `>` / `<` (visual) | Shift the selection right / left |
| `:Indent [n]` | Shift `n` lines right, starting at the cursor (default 1) |
| `:Dedent [n]` | Shift `n` lines left, starting at the cursor (default 1) |

Checked against Neovim 0.11 on the same inputs: the text and the cursor
position come out the same. Shiftwidth follows the buffer's `tab_width`;
override it with `setup{ shiftwidth = 2 }`. The new indent is rebuilt from its
width, so mixed tabs and spaces normalise to `expandtab` / `tab_width`. Empty
lines stay empty. Like Neovim's default `nostartofline`, the cursor keeps its
screen column instead of jumping to the first non-blank. Visual-block `>` / `<`
shift the text from the block's left edge, not the whole line. Banked
selection regions are shifted too, each line once. Terminal, explorer and
read-only buffers are skipped.

Not supported: a count (`3>>`, `V3>`), `.` to repeat a shift, and `>` / `<`
as operators (`>j`, `>ap`). rift doesn't pass the pending count to Lua, `.`
only replays built-in edits, and plugins have no operator-pending hook.
`:Indent 3` does the same job as `3>>`.

The dedent key is written `"<lt><lt>"`: `parse_key_sequence` reads a bare `<`
as the start of a `<...>` token, and rift drops an unparseable mapping silently.

## Neovim plugin ports

Ports of the plugins from my Neovim config. noice.nvim needs no plugin: rift's
command line is already a centered popup, and `init.lua` sets it to 60 columns
with a box border. For oil.nvim I use rift's built-in explorer (`:f`).

### plugins/comment.lua (Comment.nvim)

| Key / command | Effect |
|---|---|
| `gcc` / `gbc` | Toggle a line / block comment on the current line |
| `gc` / `gb` (visual) | Toggle line comments on the selected lines / wrap the selection in a block comment |
| `gcj` `gck`, `gc{1-9}j` `gc{1-9}k` | Toggle lines from the cursor down / up |
| `gcip` `gcap` `gcgg` `gcG` | Toggle the paragraph / to the top / to the bottom |
| `gco` `gcO` `gcA` | Start a comment below / above / at the end of the line |
| `:CommentToggle [n]` | Toggle `n` lines from the cursor |

All lines are commented at the shallowest indent, blank lines are skipped,
and a range that is fully commented is uncommented. Visual `gc`/`gb` also
acts on banked selection regions. The comment string comes from rift's
filetype, falling back to the file extension (so `.razor` uses `@* *@`).
Add more with `setup{ commentstrings = { ext = { "//%s", "/*%s*/" } } }`.

Not supported: a count before the key (`3gcc`) and arbitrary `gc{motion}`,
since rift has no operator-pending hook for plugins; the common motions are
mapped individually. Dot-repeat does not repeat a toggle.

### plugins/closetag.lua (vim-closetag)

In html, xhtml, xml, jsx, tsx, vue, svelte and php files, typing `>` to finish
an opening tag inserts the closing tag after the cursor. Typing `>` again
straight away puts the closing tag on its own line with an indented line in
between. Void elements (`<br>`, `<img>`, ...) aren't closed except in xhtml/xml.
TypeScript generics (`useState<T>`), self-closing tags and `>` inside quoted
attribute values or JSX `{...}` expressions are left alone.

`>` is only mapped while one of those files is focused. `:CloseTagToggle`
turns it off/on. The `<leader>>` "insert a plain `>`" key isn't ported:
an insert-mode mapping starting with Space would hold up every space typed.

### plugins/conform.lua (conform.nvim)

Format on save for javascript, typescript and json with prettier. rift can't
pipe a buffer to a process, so after a save the formatter runs on the file,
only the lines it changed are replaced, and the buffer is saved again. If you
switch buffers or type before it finishes, that result is dropped.

`:Format` formats on demand; `:ConformInfo` shows the formatters, the resolved
executable and the last error. prettier is looked up on PATH and in
`~/.bun/bin` (prettier.exe, .cmd or .bat). The LSP fallback is not ported.
Neovim had no language servers configured, so it never ran there either.

### plugins/splunk.lua (splunk-syntax.nvim)

SPL highlighting for `.spl` files, `.splunk` files, and the `<query>`,
`<earliest>` and `<latest>` contents of Splunk dashboard XML (any `.xml` or
`.splunk` file containing `<dashboard` or `<form`). Same token rules as the
Vim syntax file, colored with the active rift theme. Files over 5000 lines are
skipped (`setup{ max_lines = ... }`).

### plugins/open_line.lua

`o` opens a new line below with the same leading whitespace (tabs and spaces)
as the current line. Rift's built-in `o` starts at column 0.
