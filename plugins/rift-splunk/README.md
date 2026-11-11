# rift-splunk

splunk-syntax.nvim for rift: SPL syntax highlighting.

Highlights SPL in `.spl` and `.splunk` files, and the `<query>`, `<earliest>`
and `<latest>` contents of Splunk dashboard XML (any `.xml` or `.splunk` file
containing `<dashboard` or `<form`). Same token rules as the Vim syntax file,
colored with the active rift theme.

## Options

```lua
{
  max_lines = 5000,  -- skip files longer than this, to keep edits responsive
}
```

## Install

`rift-splunk.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-splunk/?.lua"
require("rift-splunk").setup({ max_lines = 10000 })
```

Tested with rift 0.7.5.
