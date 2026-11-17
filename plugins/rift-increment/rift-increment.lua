-- `<C-a>` / `<C-x>`: add to / subtract from the number at or after the
-- cursor, like Vim (nrformats=bin,hex).
--
-- Uses the number under the cursor, or the first one after it on the line.
-- Decimal numbers take a `-` right before them as their sign. `0x1f` and
-- `0b101` are hex and binary; their width and the case of hex letters are
-- kept. Leading zeros on a decimal number keep its width (007 -> 008). The
-- cursor ends on the number's last character.
--
-- rift doesn't pass counts to plugins, so `5<C-a>` adds 1. Use
-- `:Increment 5` / `:Decrement 5` for more.
local M = {}
local MODULE = ...

-- Helpers -------------------------------------------------------------------

-- rift.replace_lines drops the newline after the range, joining the next
-- line onto the last new one, and takes two undo steps. This puts the
-- newline back and, from Normal mode, wraps the edit in a brief Insert mode
-- so `u` undoes it in one step.
local function set_lines(s, e, lines)
  local out = { table.unpack(lines) }
  if #out > 0 and e < rift.get_line_count() then out[#out + 1] = "" end
  local wrap = rift.get_mode() == "normal"
  if wrap then rift.exec_action("mode:insert") end
  rift.replace_lines(s, e, out)
  if wrap then rift.exec_action("mode:normal") end
end

-- Character column -> byte index (1-based) and back.
local function char_to_byte(s, col) return utf8.offset(s, col + 1) or (#s + 1) end
local function byte_to_char(s, b) return (utf8.len(s:sub(1, b - 1)) or (b - 1)) end

-- Keymaps run the command through `:lua` so it sees the current cursor (a
-- mapped `editor:run:Command` sees the cursor from before the last motion).
local function map(mode, keys, name)
  rift.map(mode, keys, string.format("editor:run:lua _rift_commands[%q].fn({})", name))
end

-----------------------------------------------------------------------------

-- The numbers on a line, in order: { s, e, kind } with byte positions, `s`
-- including a sign or 0x/0b prefix.
local function numbers(line)
  local found, i = {}, 1
  while i <= #line do
    local s, e = line:find("0[xX]%x+", i)
    local kind = "hex"
    local bs, be = line:find("0[bB][01]+", i)
    local ds, de = line:find("%d+", i)
    if not ds then break end
    -- Prefer a hex/binary literal that starts where the next digits do.
    if s == ds then
      kind = "hex"
    elseif bs == ds then
      s, e, kind = bs, be, "bin"
    else
      s, e, kind = ds, de, "dec"
      if s > 1 and line:sub(s - 1, s - 1) == "-" then s = s - 1 end
    end
    found[#found + 1] = { s = s, e = e, kind = kind }
    i = e + 1
  end
  return found
end

local function format_number(text, kind, delta)
  if kind == "hex" then
    local prefix, digits = text:sub(1, 2), text:sub(3)
    -- Hex is unsigned 64-bit like Vim: 0x0 - 1 wraps to 0xffffffffffffffff
    -- (Lua's %x prints a negative integer as its two's complement).
    local n = math.tointeger(tonumber(digits, 16)) + delta
    local fmt = digits:match("%u") and "%0" .. #digits .. "X" or "%0" .. #digits .. "x"
    return prefix .. string.format(fmt, n)
  elseif kind == "bin" then
    local prefix, digits = text:sub(1, 2), text:sub(3)
    local n = tonumber(digits, 2) + delta
    if n < 0 then n = 0 end
    local bits = {}
    repeat
      table.insert(bits, 1, tostring(n & 1))
      n = n >> 1
    until n == 0
    local out = table.concat(bits)
    if #out < #digits then out = string.rep("0", #digits - #out) .. out end
    return prefix .. out
  else
    local neg = text:sub(1, 1) == "-"
    local digits = neg and text:sub(2) or text
    local n = tonumber(digits) * (neg and -1 or 1) + delta
    local out = tostring(math.abs(n))
    -- Leading zeros: keep the width.
    if digits:match("^0%d") and #out < #digits then
      out = string.rep("0", #digits - #out) .. out
    end
    return (n < 0 and "-" or "") .. out
  end
end

function M.add(delta)
  if rift.buf_kind() ~= "file" then return end
  local row, col = rift.get_cursor()
  local line = rift.get_lines(row, row)[1] or ""
  local cur = char_to_byte(line, col)
  for _, num in ipairs(numbers(line)) do
    if num.e >= cur then
      local text = line:sub(num.s, num.e)
      local new = format_number(text, num.kind, delta)
      local new_line = line:sub(1, num.s - 1) .. new .. line:sub(num.e + 1)
      set_lines(row, row, { new_line })
      rift.set_cursor(row, byte_to_char(new_line, num.s + #new - 1))
      return
    end
  end
end

local defaults = {
  increment = "<C-a>", -- false to disable
  decrement = "<C-x>", -- false to disable
}

function M.setup(opts)
  opts = opts or {}
  local inc = opts.increment
  if inc == nil then inc = defaults.increment end
  local dec = opts.decrement
  if dec == nil then dec = defaults.decrement end

  rift.register_command("Increment", function(args)
    M.add(tonumber(args[1]) or 1)
  end, "Add N (default 1) to the number at or after the cursor")
  rift.register_command("Decrement", function(args)
    M.add(-(tonumber(args[1]) or 1))
  end, "Subtract N (default 1) from the number at or after the cursor")
  if inc then map("n", inc, "Increment") end
  if dec then map("n", dec, "Decrement") end
end

-- Dropped straight into rift's plugins directory rather than require()d
-- from a config: set up with the defaults.
if not MODULE then M.setup() end

return M
