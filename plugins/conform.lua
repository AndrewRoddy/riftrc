-- conform.nvim for rift: format on save with external formatters.
--
-- rift can't pipe a buffer into a process, so formatting runs on the file
-- that was just written: the formatter prints the formatted file, the changed
-- lines are swapped into the buffer, and the buffer is saved again.
local M = {}

local is_windows = package.config:sub(1, 1) == "\\"

local opts = {
  format_on_save = true,
  -- Filetype -> formatters to try, first available one wins
  formatters_by_ft = {
    javascript = { "prettier" },
    typescript = { "prettier" },
    json = { "prettier" },
  },
  formatters = {
    prettier = {
      -- Installed with bun, which only makes a prettier.exe
      command = "prettier",
      -- $FILENAME is replaced with the file's path. Output goes to stdout.
      args = { "$FILENAME" },
    },
  },
  -- File extension -> filetype, matching what Neovim calls them (so .jsx is
  -- javascriptreact there and is not formatted unless added here).
  filetypes = {
    js = "javascript", mjs = "javascript", cjs = "javascript",
    ts = "typescript", mts = "typescript", cts = "typescript",
    json = "json",
  },
}

local seq = 0
local pending = {}       -- tag -> { buf, path, formatter }
local resave = {}        -- buf -> true while our own re-save is in flight
local last_error = {}    -- formatter -> message

local function filetype_of(path)
  local ext = path and path:match("%.([^.\\/]+)$")
  return ext and opts.filetypes[ext:lower()]
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

-- Finds `name` on PATH. On Windows also tries the PATHEXT-style extensions
-- and bun's install dir, since rift may not inherit the PATH Neovim was given.
local function find_executable(name)
  if name:find("[/\\]") then return file_exists(name) and name or nil end
  local dirs = {}
  if is_windows then
    local home = os.getenv("USERPROFILE")
    if home then dirs[#dirs + 1] = home .. "\\.bun\\bin" end
  end
  for dir in (os.getenv("PATH") or ""):gmatch(is_windows and "[^;]+" or "[^:]+") do
    dirs[#dirs + 1] = dir
  end
  local exts = is_windows and { ".exe", ".cmd", ".bat", "" } or { "" }
  for _, dir in ipairs(dirs) do
    for _, ext in ipairs(exts) do
      local candidate = dir .. (is_windows and "\\" or "/") .. name .. ext
      if file_exists(candidate) then return candidate end
    end
  end
  return nil
end

local function resolve_command(name)
  local cfg = opts.formatters[name]
  return cfg and find_executable(cfg.command)
end

local function formatter_for(path)
  local ft = filetype_of(path)
  if not ft then return nil end
  for _, name in ipairs(opts.formatters_by_ft[ft] or {}) do
    if opts.formatters[name] then return name end
  end
  return nil
end

local function run(buf, path, name)
  local cfg = opts.formatters[name]
  local cmd = resolve_command(name)
  if not cmd then
    last_error[name] = "'" .. cfg.command .. "' was not found on PATH"
    rift.notify("warn", "conform: " .. last_error[name])
    return
  end
  local args = {}
  for i, a in ipairs(cfg.args or { "$FILENAME" }) do
    args[i] = (a:gsub("%$FILENAME", function() return path end))
  end

  seq = seq + 1
  local tag = "conform:" .. seq
  pending[tag] = { buf = buf, path = path, formatter = name }
  rift.spawn(cmd, args, tag)
end

local function split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  return lines
end

local function trim_trailing_blank(lines)
  local n = #lines
  while n > 0 and lines[n] == "" do n = n - 1 end
  return n
end

-- Replaces only the lines that differ, so undo, the cursor and the rest of the
-- buffer are disturbed as little as possible. Returns true if anything changed.
local function apply_diff(new)
  local old = rift.get_lines(1, -1)
  local n, m = trim_trailing_blank(old), trim_trailing_blank(new)
  if n == 0 then return false end

  local p = 0
  while p < n and p < m and old[p + 1] == new[p + 1] do p = p + 1 end
  if p == n and p == m then return false end
  local q = 0
  while q < n - p and q < m - p and old[n - q] == new[m - q] do q = q + 1 end

  local s, e = p + 1, n - q
  local ns, ne = p + 1, m - q
  -- A pure insertion has no old lines to replace; widen by one shared line.
  if s > e then
    if p > 0 then
      s, ns = p, p
    else
      e, ne = 1, ne + 1
    end
    e = math.max(e, s)
  end

  local slice = {}
  for i = ns, ne do slice[#slice + 1] = new[i] end

  local row, col = rift.get_cursor()
  rift.replace_lines(s, e, slice)
  if row > e then row = row + #slice - (e - s + 1) end
  rift.set_cursor(math.max(1, row), col)
  return true
end

local function on_done(ev)
  local job = pending[ev.tag]
  pending[ev.tag] = nil

  if not ev.success then
    local msg = (ev.output or ""):match("[^\r\n]+") or "exited with an error"
    last_error[job.formatter] = ev.output
    rift.notify("warn", "conform: " .. job.formatter .. " failed: " .. msg)
    return
  end
  last_error[job.formatter] = nil

  -- Only touch the buffer if it is still the one on screen and nothing was
  -- typed since the save; otherwise the formatted text is stale.
  if rift.current_buf() ~= job.buf or rift.is_dirty() then return end
  local lines = split_lines(ev.output or "")
  -- stderr is appended to stdout; drop any warnings rather than write them
  -- into the file.
  while #lines > 0 and lines[#lines]:match("^%[warn%]") do lines[#lines] = nil end
  if apply_diff(lines) then
    resave[job.buf] = true
    rift.save()
  end
end

function M.format(buf, path)
  buf = buf or rift.current_buf()
  path = path or rift.get_filepath()
  local name = formatter_for(path)
  if not name then
    rift.notify("warn", "conform: no formatter for " .. (path and rift.fs.basename(path) or "this buffer"))
    return
  end
  if buf == rift.current_buf() and rift.is_dirty() then
    -- The formatter reads the file on disk; saving formats via BufSavePost.
    rift.save()
    return
  end
  run(buf, path, name)
end

local function info()
  local path = rift.get_filepath()
  local ft = filetype_of(path)
  local lines = {
    "File:       " .. (path or "(none)"),
    "Filetype:   " .. (ft or "(no formatter mapping)"),
    "On save:    " .. tostring(opts.format_on_save),
    "",
    "Formatters:",
  }
  local names = {}
  for name in pairs(opts.formatters) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local fts = {}
    for f, list in pairs(opts.formatters_by_ft) do
      for _, n in ipairs(list) do
        if n == name then fts[#fts + 1] = f end
      end
    end
    table.sort(fts)
    lines[#lines + 1] = string.format("  %s  ->  %s", name,
      resolve_command(name) or (opts.formatters[name].command .. " (not found)"))
    lines[#lines + 1] = "    filetypes: " .. table.concat(fts, ", ")
    if last_error[name] then
      lines[#lines + 1] = "    last error:"
      for _, l in ipairs(split_lines(last_error[name])) do
        lines[#lines + 1] = "      " .. l
      end
    end
  end
  rift.open_float("ConformInfo", lines)
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do
    if type(v) == "table" and type(opts[k]) == "table" then
      for kk, vv in pairs(v) do opts[k][kk] = vv end
    else
      opts[k] = v
    end
  end

  rift.register_command("Format", function() M.format() end, "Format the buffer with its formatter")
  rift.register_command("ConformInfo", info, "Show formatter configuration")

  -- Calling setup again only updates options; handlers are registered once.
  if M._registered then return end
  M._registered = true

  rift.on("BufSavePost", function(ev)
    if resave[ev.buf] then
      resave[ev.buf] = nil
      return
    end
    if opts.format_on_save and formatter_for(ev.path) then
      run(ev.buf, ev.path, formatter_for(ev.path))
    end
  end)

  rift.on("UserEvent", function(ev)
    if ev.name == "ShellDone" and pending[ev.tag] then on_done(ev) end
  end)
end

M._apply_diff = apply_diff

return M
