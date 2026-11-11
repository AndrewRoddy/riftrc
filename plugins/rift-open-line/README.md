# rift-open-line

`o` keeps the current line's indentation in rift.

`o` opens a new line below with the same leading whitespace (tabs and
spaces) as the current line. rift's built-in `o` starts at column 0.
`:OpenLineBelow` does the same.

No options.

## Install

`rift-open-line.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-open-line/?.lua"
require("rift-open-line").setup()
```

Tested with rift 0.7.5.
