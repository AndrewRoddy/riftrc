# riftrc

My config for [rift](https://github.com/monster0506/rift), a vim-like modal
terminal text editor. `.riftrc` files aren't supported yet, so this is a Lua
plugin instead.

## Layout

```
riftrc/
  init.lua      settings and keymaps, then require()s each plugin
  plugins/      standalone plugins, one folder each, releasable on their own
  SPEC/         what I've learned about rift, the porting plan, test tools
  treesitter/   Neovim's treesitter setup carried over (work in progress)
```

## Plugins

Each plugin is a single file with no dependencies on this config or on each
other. Copying `plugins/<name>/<name>.lua` into any rift plugins directory
installs it with the defaults; its README says how to pass options.

| Plugin | What it is |
|---|---|
| [rift-comment](plugins/rift-comment) | Comment.nvim: `gcc`, `gbc`, `gcip`, `gco`, ... |
| [rift-closetag](plugins/rift-closetag) | vim-closetag: close HTML/XML/JSX tags as you type `>` |
| [rift-conform](plugins/rift-conform) | conform.nvim: format on save with external formatters |
| [rift-splunk](plugins/rift-splunk) | splunk-syntax.nvim: SPL highlighting |
| [rift-indent](plugins/rift-indent) | `>>` / `<<` line shifting |
| [rift-open-line](plugins/rift-open-line) | `o` keeps the current line's indentation |
| [rift-join](plugins/rift-join) | `J` / `gJ` join lines exactly like Neovim |
| [rift-clipboard](plugins/rift-clipboard) | `clipboard=unnamedplus`: yanks go to the system clipboard |

noice.nvim needs no plugin: rift's command line is already a centered popup,
and `init.lua` sets it to 60 columns with a box border. For oil.nvim I use
rift's built-in explorer (`:f`).

## Installing this config

`%APPDATA%/rift/plugins` (or `~/.config/rift/plugins`) only loads top-level
`.lua` files, and that directory isn't on `package.path`, so a small loader
sits next to this repo:

```lua
-- plugins/load.lua
local dir = _rift_current_plugin_file:match("(.*)/[^/]+$")
package.path = package.path .. ';' .. dir .. '/?.lua;' .. dir .. '/?/init.lua'

require("riftrc")
```

`init.lua` then adds `riftrc/plugins/?/?.lua` to `package.path` and
`require`s each plugin with its options.

## Testing

`SPEC/tools/replay.sh <file> <keys>...` runs rift headlessly against a copy
of this directory and prints the buffer. `SPEC/tests/join.sh` checks
rift-join against Neovim. See `SPEC/SPEC.md`.
