-- splunk-syntax.nvim for rift: SPL highlighting for .spl/.splunk files, and
-- for SPL inside <query>/<earliest>/<latest> of Splunk dashboard XML.
--
-- rift has no SPL tree-sitter grammar, so this tokenizes in Lua and colors
-- tokens with annotations whose faces resolve against the active theme.
local M = {}

local NS = "splunk."

local opts = {
  -- Skip highlighting past this many lines to keep edits responsive
  max_lines = 5000,
}

-- Vim highlight group -> rift theme face
local FACES = {
  comment = "comment",
  string = "string",
  escape = "escape",
  number = "number",
  boolean = "boolean",
  null = "constant",
  boolop = "keyword.operator",
  operator = "operator",
  pipe = "operator",
  bracket = "punctuation.bracket",
  macro = "function.macro",
  command = "keyword",
  keyword = "keyword",
  ["function"] = "function",
  field = "variable",
  time = "preproc",
  tag = "tag",
}

local function words(s)
  local set = {}
  for w in s:gmatch("%S+") do set[w:lower()] = true end
  return set
end

local COMMANDS = words [[
  abstract accum accumulate addcoltotals addinfo addtotals analyzefields
  anomalies anomalydetection anomalousvalue append appendcols appendpipe
  apply arules associate audit autoregress bin bucket bucketdir chart cluster
  collect concurrency contingency convert correlate crawl datamodel dbinspect
  dbxquery dedup delete delta diff erex eval eventcount eventstats extract
  fieldformat fields fieldsummary fieldalias filldown fillnull findtypes
  folderize fit foreach format gauge gentimes geom geomfilter geostats head
  highlight history iconify input inputcsv inputlookup iplocation join kmeans
  kvform kv loadjob localize localop logreduce lookup makecontinuous
  makeresults makemv map mcatalog mcollect metadata metasearch mstats multikv
  multisearch mvcombine mvexpand noop nomv normalize outlier outputcsv
  outputlookup outputtext overlap pivot predict rangemap rare regex reltime
  relevancy rename replace rest return reverse rex rtorder run savedsearch
  score script scrub search searchtxn selfjoin sendalert sendemail sendresults
  sendsplunk set setfields sichart sirare sistats sitimechart sitop sort spath
  stats strcat streamstats table tags tail timechart timewrap transaction
  transpose trendline tstats typeahead typelearner typer uniq union untable
  walklex where x11 xmlkv xmlunescape xpath xyseries from
]]

local KEYWORDS = words [[
  by as over output outputnew groupby limit delim nullstr keepempty maxspan
  maxpause mvlist mvmax mvmin startswith connected uselookups in like notin
  span agg allnum bins bottom top cont fixedrange minspan otherstr usenull
  useother partial sep single truelabel falselabel field end start fillna
]]

local FUNCTIONS = words [[
  abs ceiling ceil floor round exp ln log pow sqrt sigfig exact len lower
  upper ltrim rtrim trim substr replace split tostring tonumber isbool isint
  isnum isstr isnull isnotnull isnan coalesce nullif mvappend mvcount mvdedup
  mvfilter mvfind mvindex mvjoin mvrange mvsort mvzip mvmap time strftime
  strptime relative_time cosh sinh tanh acos asin atan atan2 cos hypot sin tan
  pi max min random urldecode md5 sha1 sha256 sha512 typeof validate
  searchmatch match cidrmatch printf if case spath commands avg mean c count dc
  distinct_count distinctcount earliest earliest_time latest latest_time estdc
  estdc_error estdcerr exactperc first last list values median mode p perc
  percentile upperperc per_day per_hour per_minute per_second range sparkline
  stdev stdevp sum sumsq var varp json_array json_array_to_mv json_extract
  json_extract_exact json_keys json_object json_set json_set_exact json_valid
  json_append json_delete json_dict_to_mv json_mv_to_dict bool num str
  haversine
]]

local FIELDS = words [[
  _time _raw _bkt _cd _indextime _kv _serial _si _sourcetype _subsecond host
  index linecount punct source sourcetype splunk_server splunk_server_group
  timeendpos timestartpos _fullpath _multivalue _tc date_hour date_mday
  date_minute date_month date_second date_wday date_year date_zone
]]

-- Multi-char time units only, like the Vim syntax: single letters would
-- light up short variable names.
local TIME_UNITS = words [[
  sec secs second seconds min mins minute minutes hr hrs hour hours day days
  week weeks mon month months qtr quarter quarters yr year years
]]

local SNAP_UNITS = words [[
  s sec secs second seconds m min mins minute minutes h hr hrs hour hours
  d day days w week weeks mon month months q qtr quarter quarters y yr year years
]]

local BOOLEANS = words "true false"
local BOOLOPS = words "and or not"

-- Tokenizer -----------------------------------------------------------------

-- Scans `text` from byte `from` to `to` (inclusive) and calls emit(kind, s, e)
-- for each token, with 1-based inclusive byte positions.
local function tokenize(text, from, to, emit)
  local i = from
  local function find_close(close, start)
    local s, e = text:find(close, start, true)
    if not s or e > to then return to end
    return e
  end

  while i <= to do
    local c = text:sub(i, i)
    local word_before = i > 1 and text:sub(i - 1, i - 1):match("[%w_]")

    if text:sub(i, i + 2) == "```" then
      local e = find_close("```", i + 3)
      emit("comment", i, e)
      i = e + 1
    elseif text:sub(i, i + 8):lower() == "`comment(" then
      local e = find_close(")`", i + 9)
      emit("comment", i, e)
      i = e + 1
    elseif c == "`" then
      local e = find_close("`", i + 1)
      emit("macro", i, e)
      i = e + 1
    elseif text:sub(i, i + 3) == "<!--" then
      local e = find_close("-->", i + 4)
      emit("comment", i, e)
      i = e + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= to do
        local d = text:sub(j, j)
        if d == "\\" and c == '"' and text:sub(j + 1, j + 1):match("[\\n\"']") then
          emit("escape", j, j + 1)
          j = j + 2
        elseif d == c then
          break
        else
          j = j + 1
        end
      end
      local e = math.min(j, to)
      emit("string", i, e)
      i = e + 1
    elseif c == "|" then
      emit("pipe", i, i)
      i = i + 1
    elseif c == "[" or c == "]" then
      emit("bracket", i, i)
      i = i + 1
    elseif c:match("%d") or (c:match("[+-]") and text:sub(i + 1, i + 1):match("%d")) then
      -- Relative time (-24h, +7d@d) first, then plain numbers
      local sign, digits, unit = text:match("^([+-]?)(%d+)(%a+)", i)
      local len
      if unit and SNAP_UNITS[unit:lower()] and not word_before then
        len = #sign + #digits + #unit
        local snap = text:match("^@(%a+)", i + len)
        if snap and SNAP_UNITS[snap:lower()] then len = len + 1 + #snap end
        if text:sub(i + len, i + len):match("[%w_]") then len = nil end
      end
      if len then
        emit("time", i, i + len - 1)
        i = i + len
      elseif c:match("[+-]") then
        emit("operator", i, i)
        i = i + 1
      else
        local num = text:match("^%d+%.%d+", i) or text:match("^%d+", i)
        local after = text:sub(i + #num, i + #num)
        if not word_before and not after:match("[%w_]") then
          emit("number", i, i + #num - 1)
        end
        i = i + #num
      end
    elseif c:match("[=!<>]") then
      local len = text:sub(i + 1, i + 1) == "=" and 2 or 1
      emit("operator", i, i + len - 1)
      i = i + len
    elseif c:match("[%*/%%]") then
      emit("operator", i, i)
      i = i + 1
    elseif c:match("[%a_]") then
      local w = text:match("^[%w_]+", i)
      local lw = w:lower()
      local kind = COMMANDS[lw] and "command"
        or KEYWORDS[lw] and "keyword"
        or FUNCTIONS[lw] and "function"
        or FIELDS[lw] and "field"
        or BOOLEANS[lw] and "boolean"
        or lw == "null" and "null"
        or BOOLOPS[lw] and "boolop"
        or (TIME_UNITS[lw] or lw == "now") and "time"
      if kind and not word_before then emit(kind, i, i + #w - 1) end
      i = i + #w
    else
      i = i + 1
    end
  end
end

-- Splunk dashboard XML: SPL inside query/time tags, plus tags and comments.
local function tokenize_xml(text, emit)
  local spl = {}
  for _, tag in ipairs({ "query", "earliest", "latest" }) do
    local pos = 1
    while true do
      local _, open_end = text:find("<" .. tag .. ">", pos, true)
      if not open_end then break end
      local close = text:find("</" .. tag .. ">", open_end + 1, true)
      if not close then break end
      if close > open_end + 1 then spl[#spl + 1] = { open_end + 1, close - 1 } end
      pos = close
    end
  end
  table.sort(spl, function(a, b) return a[1] < b[1] end)

  local i, n = 1, #text
  local k = 1
  while i <= n do
    local region = spl[k]
    if region and i >= region[1] then
      tokenize(text, region[1], region[2], emit)
      i = region[2] + 1
      k = k + 1
    elseif text:sub(i, i + 3) == "<!--" then
      local _, e = text:find("-->", i + 4, true)
      e = e or n
      emit("comment", i, e)
      i = e + 1
    elseif text:sub(i, i) == "<" and text:sub(i + 1, i + 1):match("[%a/?!]") then
      local tag_end = text:find(">", i, true) or n
      local name_end = select(2, text:find("^</?[%w_:%.%-?!]+", i)) or i
      emit("tag", i, name_end)
      -- Attribute values inside the tag
      local j = name_end + 1
      while j < tag_end do
        local q = text:sub(j, j)
        if q == '"' or q == "'" then
          local close = text:find(q, j + 1, true) or tag_end
          emit("string", j, math.min(close, tag_end))
          j = close + 1
        else
          j = j + 1
        end
      end
      emit("tag", tag_end, tag_end)
      i = tag_end + 1
      while spl[k] and spl[k][2] < i do k = k + 1 end
    else
      i = i + 1
    end
  end
end

-- Detection ------------------------------------------------------------------

-- Only these can hold SPL, so other buffers return before reading any lines.
local CANDIDATE_EXT = { spl = true, splunk = true, xml = true }

local function is_dashboard(text)
  return text:find("<dashboard[%s/>]") ~= nil or text:find("<form[%s/>]") ~= nil
end

-- "splunk", "splunkxml" or nil, matching splunk-syntax.nvim's ftdetect.
function M.detect(path, text)
  local ext = path and path:match("%.([^.\\/]+)$")
  ext = ext and ext:lower()
  if ext == "spl" then return "splunk" end
  if ext == "splunk" then return is_dashboard(text) and "splunkxml" or "splunk" end
  if ext == "xml" and is_dashboard(text) then return "splunkxml" end
  return nil
end

-- Highlighting --------------------------------------------------------------

function M.highlight()
  if rift.buf_kind() ~= "file" then return end
  local path = rift.get_filepath()
  local ext = path and path:match("%.([^.\\/]+)$")
  if not ext or not CANDIDATE_EXT[ext:lower()] then return end
  if rift.get_line_count() > opts.max_lines then return end

  local text = table.concat(rift.get_lines(1, -1), "\n")
  local ft = M.detect(path, text)
  rift.annotations.clear(NS)
  if not ft then return end

  local function emit(kind, s, e)
    if e >= s then
      -- Annotation ranges are 0-based, end-exclusive byte offsets
      rift.annotations.add { kind = NS .. kind, range = { s - 1, e }, owner = "plugin" }
    end
  end
  if ft == "splunk" then
    tokenize(text, 1, #text, emit)
  else
    tokenize_xml(text, emit)
  end
end

function M.setup(user_opts)
  for k, v in pairs(user_opts or {}) do opts[k] = v end

  for kind, face in pairs(FACES) do
    rift.annotations.register_kind(NS .. kind, { face = face, description = "Splunk " .. kind })
  end

  rift.register_command("SplunkHighlight", M.highlight, "Re-highlight Splunk SPL in this buffer")

  -- Calling setup again only updates options; handlers are registered once.
  if M._registered then return end
  M._registered = true
  rift.on("BufOpen", M.highlight)
  rift.on("BufEnter", M.highlight)
  rift.on("BufReload", M.highlight)
  rift.on("TextChangedCoarse", M.highlight)
end

M._tokenize = tokenize
M._tokenize_xml = tokenize_xml

return M
