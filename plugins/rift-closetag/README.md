# rift-closetag

vim-closetag for rift: close HTML/XML/JSX tags as you type them.

In html, xhtml, xml, jsx, tsx, vue, svelte and php files, typing `>` to finish
an opening tag inserts the closing tag after the cursor. Typing `>` again
straight away puts the closing tag on its own line with an indented line in
between. Void elements (`<br>`, `<img>`, ...) aren't closed except in xhtml
and xml. TypeScript generics (`useState<T>`), self-closing tags and `>` inside
quoted attribute values or JSX `{...}` expressions are left alone.

`>` is only mapped while one of those files is focused. `:CloseTagToggle`
turns it off and on.

## Options

```lua
{
  extensions = { "html", "htm", "xhtml", "xml", "jsx", "tsx", "vue", "svelte", "php" },
  void_elements = { "area", "base", "br", "col", "embed", "hr", "img", "input",
                    "link", "meta", "param", "source", "track", "wbr" },
  xhtml_extensions = { "xhtml", "xml" },  -- where void elements are closed too
}
```

## Limitations

vim-closetag's `<leader>>` (type a plain `>`) isn't ported: an insert-mode
mapping starting with Space would delay every space typed.

## Install

`rift-closetag.lua` is the whole plugin and has no dependencies. Copy it into
rift's plugins directory (`%APPDATA%\rift\plugins` on Windows,
`~/.config/rift/plugins` elsewhere). rift loads it at startup, and it sets
itself up with the defaults.

To pass options, put it where rift won't load it by itself (any
subdirectory) and `require` it from one of your own plugin files:

```lua
package.path = package.path .. ";" .. "/path/to/rift-closetag/?.lua"
require("rift-closetag").setup({ extensions = { "html", "vue" } })
```

Tested with rift 0.7.5.
