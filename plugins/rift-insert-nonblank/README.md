# rift-insert-nonblank

Neovim's `I` for rift. rift's `I` starts inserting at column 0, before the
indent. This plugin makes it start at the first non-blank character, as
Neovim's does.

| Key | Does |
|---|---|
| `I` | Insert before the first non-blank character (at the end of a line that is only whitespace) |
| `gI` | Insert at column 0 (rift's old `I`, Neovim's `gI`) |

`I` in Visual mode is left to rift, which inserts on every selected line.

## Limitations

- `.` after `I` repeats as `i` at the cursor, not at the first non-blank.
  The plugin moves the cursor and then starts a plain insert, and that
  plain insert is what rift records.
- No count (`3Ifoo`): rift drops counts before mapped keys.

## Options

```lua
require("rift-insert-nonblank").setup({
  mappings = true,  -- false: only the :InsertNonblank command
})
```

## Tests

`bash tests/insert_nonblank.sh` types keys into headless rift with
`rift-replay` (it comes with rift) and checks the resulting lines.

## Install

Copy `rift-insert-nonblank.lua` into rift's plugins directory
(`%APPDATA%\rift\plugins` on Windows, `~/.config/rift/plugins` elsewhere).
It sets itself up with the defaults.

Tested with rift 0.7.7.
