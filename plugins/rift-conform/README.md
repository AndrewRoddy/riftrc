# rift-conform

conform.nvim for rift: format files on save with external formatters.

After a save, the formatter runs on the file, only the lines it changed are
replaced in the buffer, and the buffer is saved again. rift can't pipe a
buffer into a process, so this formats the saved file. If you switch buffers
or type before it finishes, the result is dropped.

| Command | Effect |
|---|---|
| `:Format` | Format the current buffer now |
| `:ConformInfo` | Show the formatters, the executable found and the last error |

Out of the box it runs prettier on JavaScript, TypeScript and JSON.
Executables are looked up on `PATH` and in `~/.bun/bin` (`.exe`, `.cmd`,
`.bat` on Windows).

## Options

```lua
{
  format_on_save = true,
  formatters_by_ft = {            -- filetype -> formatters, first found wins
    javascript = { "prettier" },
  },
  formatters = {
    prettier = { command = "prettier", args = { "$FILENAME" } },  -- prints to stdout
  },
  filetypes = { js = "javascript" },  -- file extension -> filetype
}
```

## Limitations

No LSP formatting fallback, and formatters that only read stdin aren't
supported yet.

## Install

`rift-conform.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-conform/?.lua"
require("rift-conform").setup({ format_on_save = true })
```

Tested with rift 0.7.5.
