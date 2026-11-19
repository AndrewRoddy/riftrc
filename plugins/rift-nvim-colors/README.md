# rift-nvim-colors

rift's syntax colors, set to what my Neovim draws: `#ff922f` keywords,
`#8ec07c` functions, `#fabd2f` types, `#b8bb26` strings, `#d3869b` numbers
and constants, `#83a598` builtins and specials, `#928374` comments, and
`#EBDBB2` for variables, operators and punctuation.

| Color | Neovim groups (my config) | rift captures |
|---|---|---|
| `#ff922f` | Keyword, Statement, PreProc | `keyword.*`, `conditional`, `repeat`, `preproc`, `label`, `attribute`, ... |
| `#8ec07c` | Function | `function.*`, `method`, `method.call` |
| `#fabd2f` | Type | `type`, `type.builtin` |
| `#b8bb26` | String, Character | `string`, `character` |
| `#d3869b` | Number, Boolean, Constant | `number`, `float`, `boolean`, `constant` |
| `#83a598` | Special, `@module`, `@*.builtin` | `module`, `constant.builtin`, `variable.builtin`, `string.escape`, `tag`, ... |
| `#928374` | Comment | `comment` |
| `#EBDBB2` | Identifier, Operator, Delimiter | `variable.*`, `property`, `operator`, `punctuation.*` |

It doesn't run Neovim. The colors are a table in `rift-nvim-colors.lua`
(laid out like `code_colors` in my Neovim config). rift's tree-sitter
highlighting does the rest, live as you type, through `rift.highlight.set`.
That also colors rift-splunk, whose highlighting uses the same groups.

## How the table was made

`tools/resolve.lua` runs inside Neovim with my config and asks what style
Neovim's highlighter gives each capture name that rift's queries use
(`tools/captures.txt`). It applies the same fallback Neovim does
(`@keyword.return` → `@keyword`), so groups my config doesn't set get
Neovim's default links: `@attribute` is `PreProc` (`#ff922f`), `@tag` is
`Special` (`#83a598`), and so on. All 72 captures in rift 0.7.7 come out the
same in rift as in Neovim.

Some of rift's queries use older capture names. Those get the color of the
name Neovim's queries use now, so `if` is a keyword in both:

| rift | Neovim |
|---|---|
| `conditional`, `repeat` | `@keyword.conditional`, `@keyword.repeat` |
| `field`, `parameter` | `@variable.member`, `@variable.parameter` |
| `method`, `method.call` | `@function.method`, `@function.method.call` |
| `storageclass`, `type.qualifier` | `@keyword.modifier` |
| `preproc` | `@keyword.directive` |
| `text.title`, `text.uri`, `text.literal` | `@markup.heading`, `@markup.link.url`, `@markup.raw` |

To redo it after changing my Neovim colors, run this from this folder and
update the tables to match:

```sh
nvim --headless -i NONE -c "luafile tools/resolve.lua" -c "qa!"
```

## Limitations

- Same colors, not the same parsing. rift's grammars and queries aren't
  nvim-treesitter's, so a few tokens are captured differently (one may
  call something a `variable` where the other says `property`). For an
  exact match, rift-nvim-syntax asks a headless Neovim instead, but it's
  slower.
- The background and normal text (`#282820` / `#EBDBB2`) come from rift's
  `gruvbox` theme, which `init.lua` sets.

## Options

```lua
require("rift-nvim-colors").setup({
  -- Override single groups, applied after the colors above.
  styles = { comment = { fg = "#928374", italic = true } },
})
```

`:NvimColors` applies the colors again.

## Install

Copy `rift-nvim-colors.lua` into rift's plugins directory
(`%APPDATA%\rift\plugins` on Windows, `~/.config/rift/plugins` elsewhere).
It sets itself up with the defaults.

Tested with rift 0.7.7.
