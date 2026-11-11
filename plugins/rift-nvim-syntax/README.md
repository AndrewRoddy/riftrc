# rift-nvim-syntax

Syntax highlighting in [rift](https://github.com/monster0506/rift) that is
exactly your Neovim's: same parsers, same queries, same colors, bold,
italic, underline and strikethrough.

It doesn't imitate Neovim, it asks it. A headless `nvim --clean` parses the
buffer with the parsers and queries from your Neovim setup (nvim-treesitter,
injections, `#set! priority`, your own `queries/`), resolves every capture to
the look your config gives it, and hands back byte ranges. rift draws them
over its own highlighting.

Checked against what Neovim actually draws, through a real UI client, for
C, CSS, Go, HTML (with `<style>`/`<script>`), JavaScript, JSON, Lua,
Markdown (with code blocks), PowerShell, Python, Rust, shell, TOML,
TypeScript, TSX, YAML, and custom parsers (psu, Splunk, Splunk dashboards).
Every byte matches: color, bold, italic, underline, strikethrough and
background.

## Requirements

- Neovim 0.10+ on `PATH`, with your tree-sitter parsers installed
  (nvim-treesitter or `site/parser`).
- Plugins installed by lazy.nvim (`stdpath("data")/lazy/*`) are found
  automatically, as is your config directory (`queries/`, `ftdetect/`).

## Install

Copy `rift-nvim-syntax.lua` into your rift plugins directory
(`%APPDATA%/rift/plugins` or `~/.config/rift/plugins`). It sets itself up with
the defaults. To pass options, `require` it from your own config instead:

```lua
require("rift-nvim-syntax").setup({
  nvim = "nvim",
  max_bytes = 300000,
  -- Anything your config does to tree-sitter outside of queries:
  nvim_init = [[
    vim.treesitter.language.register("xml", "splunkxml")
  ]],
})
```

Use `:set theme gruvbox` (or set the background/foreground) to match
Neovim's `Normal` colors. This plugin only colors the text.

## Options

| Option | Default | |
|---|---|---|
| `nvim` | `"nvim"` | Neovim executable (name on `PATH` or a full path) |
| `max_bytes` | `300000` | Larger buffers keep rift's own highlighting |
| `nvim_init` | `""` | Lua run in the headless Neovim before parsing: custom predicates, `language.register`, ... |
| `cache_dir` | `%TEMP%/rift-nvim-syntax` | Scripts, the color dump and buffer copies |

## Commands

- `:NvimSyntax`: re-highlight the current buffer.
- `:NvimSyntaxColors`: reload colors from your Neovim config, then
  re-highlight. Do this after changing your colorscheme. (They're also
  refreshed in the background each time rift starts.)

## How it works

- **Colors.** A headless `nvim` with your full config dumps every highlight
  group (links resolved: fg, bg, bold/italic/underline/strikethrough/reverse)
  to `colors-v2.lua`. This happens
  once per rift session, in the background (the first ever run waits for
  it). Each refresh then runs `nvim --clean`, which takes about 0.1 s
  instead of starting your whole config.
- **Highlighting.** The same rules as `vim.treesitter.highlighter`: every
  tree including injections, in `for_each_tree` order. On each byte the
  captures stack from lowest priority to highest (the later capture on top
  for a tie) and combine like Neovim's: the top one that sets a color wins,
  and bold/italic/... add up (`nocombine` resets them). `@capture.lang`
  falls back to parent groups (`@keyword.function` → `@keyword`).
- **Drawing.** Each distinct look becomes one annotation kind
  (`nvim-syntax.ff922f-b`), registered once with its style, and each run of
  text is an annotation of that kind (the same way
  [rift-markdown](https://github.com/Monster0506/rift-markdown) styles
  headings).
- **When.** On opening or entering a buffer, on CursorHold when the text
  changed since the last run, and right after an edit that leaves the
  cursor where it was (`x`, `r` at the cursor), since CursorHold doesn't
  fire twice at one position. The run is synchronous, about 0.1–0.2 s for a
  typical file, because a rift plugin only gets a background process's
  result when something else happens (a key or CursorHold). Text edited
  since the last run shows rift's own colors until the next one.

## Limitations

- LSP semantic tokens aren't included. Neovim colors some tokens from the
  language server on top of tree-sitter (clangd marks operators and types,
  for example), so those can differ.
- Highlights from other Neovim plugins (color swatches, ...) aren't
  included. Undercurl and the other underline styles draw as a plain
  underline, and the underline color isn't kept.
- `dd`, `d{motion}` and `c{motion}` that leave the cursor in place don't
  refresh until the cursor next moves: rift gives plugins no event after
  them.
- rift waits for each run. On very large files that's noticeable, which is
  what `max_bytes` is for.
