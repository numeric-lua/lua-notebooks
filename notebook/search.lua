--
-- Pure literal search helpers shared by the notebook find/replace overlays and
-- the document model.  Everything is byte-oriented and Lua 5.1 compatible.
--
local Search = {}

local function normalise(options)
  options = options or {}
  return {
    case_sensitive = options.case_sensitive == true,
    whole_word = options.whole_word == true,
    include_output = options.include_output ~= false,
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

local function next_match(haystack, needle, position)
  return haystack:find(needle, position, true)
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

-- Return the 1-based start/end offsets of every non-overlapping occurrence.
function Search.matches(text, query, options)
  local haystack, needle, opts = prepare(text, query, options)
  if haystack == nil then return {} end
  local result = {}
  local position = 1
  while position <= #haystack do
    local first, last = next_match(haystack, needle, position)
    if first == nil then break end
    if boundary_ok(text or "", first, last, opts.whole_word) then
      result[#result + 1] = { first, last }
      position = last + 1
    else
      position = first + 1
    end
  end
  return result
end

function Search.count_text(text, query, options)
  return #Search.matches(text, query, options)
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
      local matches = Search.matches(line, query, opts)
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
        local matches = Search.matches(line, query, opts)
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
    local rows, notebook_total = Search.collect(notebook.cells or {}, query,
      opts)
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

-- Replace literal text.  The replacement is inserted verbatim, so `%` and
-- captures in the replacement have no special meaning.
function Search.replace_text(text, query, replacement, options)
  text = text or ""
  local haystack, needle, opts = prepare(text, query, options)
  if haystack == nil then return text, 0 end
  replacement = replacement or ""
  local out, position, total = {}, 1, 0
  while position <= #haystack do
    local first, last = next_match(haystack, needle, position)
    if first == nil then break end
    if boundary_ok(text, first, last, opts.whole_word) then
      out[#out + 1] = text:sub(position, first - 1)
      out[#out + 1] = replacement
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
