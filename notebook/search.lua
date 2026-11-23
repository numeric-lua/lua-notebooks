--
-- Pure search helpers shared by the notebook find/replace overlays and the
-- document model.  Literal matching is the default; `regex = true` switches to
-- Lua patterns and numbered capture replacement.  Everything is byte-oriented
-- and Lua 5.1 compatible.
--
local Search = {}

local function normalise(options)
  options = options or {}
  return {
    case_sensitive = options.case_sensitive == true,
    whole_word = options.whole_word == true,
    include_output = options.include_output ~= false,
    regex = options.regex == true,
    limit = options.limit,
  }
end

local function is_word_char(character)
  return character ~= nil and character ~= "" and
    character:match("[%w_]") ~= nil
end

local function boundary_ok(text, first, last, whole_word)
  if not whole_word then return true end
  local before = first > 1 and text:sub(first - 1, first - 1) or ""
  local after = last < #text and text:sub(last + 1, last + 1) or ""
  return not is_word_char(before) and not is_word_char(after)
end

-- A literal search uses plain find.  A pattern search goes through pcall so a
-- malformed user pattern is reported instead of crashing the overlay.
local function next_match(haystack, needle, position, regex)
  if not regex then return haystack:find(needle, position, true) end
  local ok, first, last = pcall(string.find, haystack, needle, position)
  if not ok then return nil, nil, tostring(first) end
  return first, last
end

local function prepare(text, query, options)
  if type(query) ~= "string" or query == "" then return nil end
  local opts = normalise(options)
  local haystack = text or ""
  local needle = query
  if not opts.case_sensitive then
    haystack = haystack:lower()
    needle = needle:lower()
  end
  return haystack, needle, opts
end

-- Exposed so the overlays can label a malformed pattern before it is used.
function Search.validate(query, options)
  if type(query) ~= "string" or query == "" then return true end
  local opts = normalise(options)
  if not opts.regex then return true end
  local ok, err = pcall(string.find, "", query)
  if ok then return true end
  return false, tostring(err)
end

-- Return the 1-based start/end offsets of every non-overlapping occurrence.
-- A second return value carries a pattern error when the query is malformed.
function Search.matches(text, query, options)
  local haystack, needle, opts = prepare(text, query, options)
  if haystack == nil then return {} end
  local result = {}
  local position = 1
  while position <= #haystack do
    local first, last, err = next_match(haystack, needle, position, opts.regex)
    if err ~= nil then return result, err end
    if first == nil then break end
    if last < first then
      -- Empty pattern match: record nothing and make progress by one byte.
      position = first + 1
    elseif boundary_ok(text or "", first, last, opts.whole_word) then
      result[#result + 1] = { first, last }
      position = last + 1
    else
      position = first + 1
    end
  end
  return result
end

function Search.count_text(text, query, options)
  local matches = Search.matches(text, query, options)
  return #matches
end

-- Collect one result row per matching source or output line.  `total` counts
-- every occurrence, while `limit` only bounds the returned rows used by the
-- overlay list.
function Search.collect(cells, query, options)
  local opts = normalise(options)
  local results, total = {}, 0
  if type(query) ~= "string" or query == "" then return results, total end
  for cell_index, cell in ipairs(cells or {}) do
    local source = type(cell.source) == "string" and cell.source or ""
    local offset = 1
    for line in (source .. "\n"):gmatch("(.-)\n") do
      local matches, err = Search.matches(line, query, opts)
      if err ~= nil then return results, total, err end
      total = total + #matches
      if #matches > 0 and (opts.limit == nil or #results < opts.limit) then
        results[#results + 1] = {
          cell = cell_index,
          line = line,
          cursor = offset + matches[1][1] - 1,
          count = #matches,
        }
      end
      offset = offset + #line + 1
    end
    if opts.include_output and type(cell.output) == "string" and
       cell.output ~= "" then
      for line in (cell.output .. "\n"):gmatch("(.-)\n") do
        local matches, err = Search.matches(line, query, opts)
        if err ~= nil then return results, total, err end
        total = total + #matches
        if #matches > 0 and (opts.limit == nil or #results < opts.limit) then
          results[#results + 1] = {
            cell = cell_index,
            line = "out: " .. line,
            cursor = #source + 1,
            count = #matches,
          }
        end
      end
    end
  end
  return results, total
end

function Search.count(cells, query, options)
  local _, total = Search.collect(cells, query, options)
  return total
end

-- Search across several open notebooks.  Rows keep the owning notebook index
-- and title so the overlay can switch tabs and jump to the exact cell without
-- re-running the search.  `limit` still bounds only the returned rows.
function Search.collect_notebooks(notebooks, query, options)
  local opts = normalise(options)
  local results, total = {}, 0
  if type(query) ~= "string" or query == "" then return results, total end
  for notebook_index, notebook in ipairs(notebooks or {}) do
    local rows, notebook_total, err = Search.collect(notebook.cells or {}, query,
      opts)
    if err ~= nil then return results, total, err end
    total = total + notebook_total
    for _, row in ipairs(rows) do
      if opts.limit == nil or #results < opts.limit then
        results[#results + 1] = {
          notebook = notebook_index,
          title = notebook:title(),
          name = notebook.name,
          cell = row.cell,
          line = row.line,
          cursor = row.cursor,
          count = row.count,
        }
      end
    end
  end
  return results, total
end

-- Replace literal text, or expand `%0`-`%9` captures in a pattern replacement.
-- The replacement is inserted verbatim in literal mode, so `%` has no special
-- meaning there.
function Search.replace_text(text, query, replacement, options)
  text = text or ""
  local haystack, needle, opts = prepare(text, query, options)
  if haystack == nil then return text, 0 end
  replacement = replacement or ""
  local out, position, total = {}, 1, 0
  while position <= #haystack do
    local first, last, err = next_match(haystack, needle, position, opts.regex)
    if err ~= nil then return text, 0, err end
    if first == nil then break end
    if last < first then
      position = first + 1
    elseif boundary_ok(text, first, last, opts.whole_word) then
      out[#out + 1] = text:sub(position, first - 1)
      if opts.regex then
        local matched = text:sub(first, last)
        local source = opts.case_sensitive and matched or matched:lower()
        local ok, expanded = pcall(string.gsub, source, needle, replacement, 1)
        out[#out + 1] = ok and expanded or replacement
      else
        out[#out + 1] = replacement
      end
      position = last + 1
      total = total + 1
    else
      out[#out + 1] = text:sub(position, first)
      position = first + 1
    end
  end
  if total == 0 then return text, 0 end
  out[#out + 1] = text:sub(position)
  return table.concat(out), total
end

-- Replace across cells, returning the total count and whether anything
-- changed.  Cursors are clamped so a shrunken source never points past its
-- final byte.
function Search.replace_cells(cells, query, replacement, options)
  local total, changed = 0, false
  for _, cell in ipairs(cells or {}) do
    if type(cell.source) == "string" then
      local source, count = Search.replace_text(cell.source, query,
        replacement, options)
      if count > 0 then
        cell.source = source
        local cursor = cell.cursor or (#source + 1)
        if cursor > #source + 1 then cursor = #source + 1 end
        if cursor < 1 then cursor = 1 end
        cell.cursor = cursor
        total = total + count
        changed = true
      end
    end
  end
  return total, changed
end

return Search
