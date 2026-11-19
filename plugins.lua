-- My plugins, for riftpm (github.com/Monster0506/riftpm). init.lua hands
-- this list to riftpm. They all load at startup, in the order listed.
--
-- `{ "AndrewRoddy/<name>" }` plugins are public on GitHub. riftpm clones
-- them (`:PluginSync`) and `:PluginUpdate` pulls changes I've pushed.
--
-- `repo(...)` plugins have their own repos too, but they aren't public yet.
-- On a machine with my copy in C:/Coding, riftpm loads that one. Once a repo
-- is public, switch it to the GitHub form.
--
-- `mine(...)` plugins live in this repo, in plugins/<name>/<name>.lua. riftpm
-- loads them by require()ing `main`, so they don't set themselves up and
-- riftpm calls setup(opts) instead.
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("(.*)/")
package.path = package.path .. ";" .. here .. "/plugins/?/?.lua"

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

-- A plugin in this repo. `spec` adds riftpm fields (opts, enabled, ...).
local function mine(name, spec)
  spec = spec or {}
  spec.name, spec.dir, spec.main = name, here .. "/plugins/" .. name, name
  return spec
end

-- A plugin with its own repo. `spec` adds riftpm fields (opts, ...).
local function repo(name, spec)
  spec = spec or {}
  local dev = "C:/Coding/" .. name
  if exists(dev .. "/init.lua") then
    spec.name, spec.dir = name, dev
  else
    spec[1] = "AndrewRoddy/" .. name
  end
  return spec
end

-- riftquire's code is in lua/riftquire/init.lua, which riftpm doesn't add to
-- the path itself.
local riftquire = "C:/Coding/riftquire"
package.path = package.path .. ";" .. riftquire .. "/lua/?/init.lua"

local plugins = {
  repo("rift-indent"),          -- `>>` / `<<` line shifting
  mine("rift-comment"),         -- Comment.nvim
  mine("rift-closetag"),        -- vim-closetag
  { "AndrewRoddy/rift-conform" }, -- conform.nvim
  mine("rift-nvim-colors"),     -- syntax colors from my Neovim config (#ff922f keywords, ...)
  -- Off: syntax highlighting exactly like Neovim's (asks a headless nvim).
  -- To turn it on, drop `enabled = false` here and turn off rift-splunk,
  -- which it covers.
  mine("rift-nvim-syntax", {
    enabled = false,
    opts = {
      -- What lua/nvimrc/treesitter.lua does besides queries: Splunk
      -- dashboards are XML with SPL injected, gated on the splunkxml filetype.
      nvim_init = [[
        vim.treesitter.language.register("xml", "splunkxml")
        vim.treesitter.query.add_predicate("splunkxml?", function(_, _, source)
          return type(source) == "number" and vim.bo[source].filetype == "splunkxml"
        end, { force = true })
      ]],
    },
  }),
  repo("rift-splunk"),          -- Splunk (SPL) highlighting
  mine("rift-open-line"),       -- `o` keeps the line's indent
  { "AndrewRoddy/rift-join" },  -- `J` / `gJ` join lines like Neovim
  mine("rift-clipboard"),       -- clipboard=unnamedplus: yanks go to the system clipboard
  { "AndrewRoddy/rift-fold" },  -- zc/zo/za/zR/zM indent folding
  repo("rift-term-scroll"),     -- scroll terminal history with k/j/<C-b>/<C-f> after Alt+a
  repo("rift-increment"),       -- <C-a> / <C-x> add to / subtract from a number
  -- Off for now: needs rift.term_send, which released rift doesn't have yet.
  mine("rift-rerun", { enabled = false }), -- Alt+r / Alt+Shift+r re-run the last / second-last terminal command
  mine("rift-insert-nonblank"), -- `I` inserts at the first non-blank, like Neovim
  repo("rift-jumplist"),        -- <C-o> / <C-i> jump list
  -- vimquire for rift: :Search, :SearchSources, ... Skipped if the repo
  -- isn't on this machine.
  {
    dir = riftquire, name = "riftquire", main = "riftquire",
    cond = function() return exists(riftquire .. "/lua/riftquire/init.lua") end,
  },
}

-- riftpm loads by priority (higher first) and doesn't keep the list order
-- for ties, so number them to keep it.
for i, p in ipairs(plugins) do p.priority = p.priority or (1000 - i) end

return plugins
