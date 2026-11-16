# rift-rerun

Re-run a previous shell command from a terminal buffer, without leaving
terminal mode.

| Key | Types | Does |
|---|---|---|
| `<A-r>` | Up, Enter | Run the last command again |
| `<A-S-r>` | Up, Up, Enter | Run the command before that |

**Skipping `clear`:** if the screen shows nothing but the prompt, the last
command was almost certainly `clear` / `cls`, so one extra Up is sent and
`<A-r>` re-runs the command before the clear. This reads the terminal's own
screen rather than a history file, because PowerShell's history file is shared
by every open shell and bash only writes its history on exit. It can't tell
two `clear`s in a row apart.

The keys work only in terminal (insert) mode; elsewhere they do nothing.
`:TermRerun` and `:TermRerun2` do the same thing.

Needs `rift.term_send`, which writes text to the terminal's shell. That's on
rift's `lua-term-send` branch; without it the keys show an error.

## Options

```lua
require("rift-rerun").setup({
  key = "<A-r>",          -- false to disable
  key_back2 = "<A-S-r>",  -- false to disable
  skip_clear = true,      -- step over a `clear`
})
```
