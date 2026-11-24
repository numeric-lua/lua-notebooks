--
-- .luanb persistence.  Pure encode/decode is testable without LÖVR; save/load
-- use the LÖVR filesystem, which confines writes to the app save directory.
--
local json = require("notebook.json")
local Notebook = require("notebook.model")
local Polar = require("notebook.polar")

local Format = {}

function Format.encode(notebook)
  local cells = {}
  for _, cell in ipairs(notebook.cells) do
    cells[#cells + 1] = {
      id = cell.id,
      kind = cell.kind,
      source = cell.source,
      output = cell.output or "",
      scene = cell.scene,
      widgets = cell.widgets or {},
      collapsed = cell.collapsed and true or false,
      output_expanded = cell.output_expanded and true or false,
    }
  end
  return json.encode({
    version = 1,
    name = notebook.name,
    cells = cells,
  })
end

function Format.decode(text)
  local data = json.decode(text)
  if type(data) ~= "table" or data.version ~= 1 then
    error("notebook: unsupported or missing version", 2)
  end
  if type(data.name) ~= "string" or data.name == "" then
    error("notebook: missing name", 2)
  end
  if type(data.cells) ~= "table" or #data.cells == 0 then
    error("notebook: missing cells", 2)
  end
  local cells = {}
  for index, cell in ipairs(data.cells) do
    if type(cell) ~= "table" then
      error("notebook: cell " .. index .. " is not a table", 2)
    end
    if cell.kind ~= "code" and cell.kind ~= "markdown" then
      error("notebook: invalid cell kind at " .. index, 2)
    end
    cells[index] = {
      id = cell.id,
      kind = cell.kind,
      source = type(cell.source) == "string" and cell.source or "",
      output = type(cell.output) == "string" and cell.output or "",
      scene = cell.scene,
      widgets = type(cell.widgets) == "table" and cell.widgets or {},
      collapsed = cell.collapsed == true,
      output_expanded = cell.output_expanded == true,
      running = false,
    }
  end
  return Notebook.new({ name = data.name, cells = cells })
end

function Format.save_path(notebook, path)
  local handle, err = io.open(path, "wb")
  if handle == nil then return nil, "cannot write " .. path .. ": " .. tostring(err) end
  handle:write(Format.encode(notebook))
  handle:close()
  notebook._path = path
  return path
end

function Format.save(notebook)
  local directory = "notebooks"
  lovr.filesystem.createDirectory(directory)
  local path = directory .. "/" .. notebook.name
  lovr.filesystem.write(path, Format.encode(notebook))
  return path, lovr.filesystem.getSaveDirectory() .. "/" .. path
end

local function autosave_name(notebook)
  local name = notebook.name:gsub("%.luanb$", "")
  name = name:gsub("[^%w_.-]", "_")
  return name
end

function Format.autosave_path(notebook)
  return "autosaves/" .. autosave_name(notebook) .. ".luanb"
end

function Format.write_autosave(notebook)
  if not (lovr and lovr.filesystem) then return nil, "filesystem unavailable" end
  lovr.filesystem.createDirectory("autosaves")
  local path = Format.autosave_path(notebook)
  lovr.filesystem.write(path, Format.encode(notebook))
  return path
end

function Format.load_autosave(notebook)
  if not (lovr and lovr.filesystem) then return nil, "filesystem unavailable" end
  local text = lovr.filesystem.read(Format.autosave_path(notebook))
  if text == nil then return nil, "no autosave" end
  local ok, decoded = pcall(Format.decode, text)
  if not ok then return nil, tostring(decoded) end
  return decoded
end

function Format.remove_autosave(notebook)
  if not (lovr and lovr.filesystem) then return end
  pcall(lovr.filesystem.remove, Format.autosave_path(notebook))
end

function Format.encode_session(paths, active_path)
  return json.encode({ paths = paths or {}, active = active_path })
end

function Format.decode_session(text)
  local ok, value = pcall(json.decode, text or "")
  if not ok or type(value) ~= "table" or type(value.paths) ~= "table" then
    return nil, "invalid session file"
  end
  local paths = {}
  for _, path in ipairs(value.paths) do
    if type(path) == "string" then paths[#paths + 1] = path end
  end
  return paths, type(value.active) == "string" and value.active or nil
end

function Format.encode_recent(paths)
  return json.encode({ paths = paths or {} })
end

function Format.decode_recent(text)
  local ok, value = pcall(json.decode, text or "")
  if not ok or type(value) ~= "table" or type(value.paths) ~= "table" then
    return {}
  end
  local paths = {}
  for _, path in ipairs(value.paths) do
    if type(path) == "string" then paths[#paths + 1] = path end
  end
  return paths
end

-- Aggregate markdown tags across open notebooks for the tag-index overlay.
-- Entries stay in first-seen order and remember which notebook owns each use.
function Format.tag_index(notebooks)
  local entries, by_tag = {}, {}
  for notebook_index, notebook in ipairs(notebooks or {}) do
    local counts, order = Format.tags(notebook.cells)
    for _, tag in ipairs(order) do
      local entry = by_tag[tag]
      if entry == nil then
        entry = { tag = tag, count = 0, notebooks = {} }
        by_tag[tag] = entry
        entries[#entries + 1] = entry
      end
      entry.count = entry.count + counts[tag]
      entry.notebooks[#entry.notebooks + 1] = {
        index = notebook_index,
        title = notebook:title(),
        count = counts[tag],
      }
    end
  end
  return entries
end

-- Compact, deterministic duration text for the optional cell timing label.
function Format.duration(seconds)
  if type(seconds) ~= "number" then return nil end
  if seconds < 0 then seconds = 0 end
  if seconds < 0.001 then return "<1 ms" end
  local milliseconds = seconds * 1000
  if milliseconds < 10 then return string.format("%.1f ms", milliseconds) end
  if milliseconds < 1000 then return string.format("%.0f ms", milliseconds) end
  if seconds < 60 then return string.format("%.2f s", seconds) end
  return string.format("%.1f min", seconds / 60)
end

-- Sum the recorded per-cell timings, ignoring cells that have never run.  Used
-- by the status bar after Run All so the optional timing stays useful without
-- widening the cell layout.
function Format.total_elapsed(cells)
  local total, count = 0, 0
  for _, cell in ipairs(cells or {}) do
    if type(cell.elapsed) == "number" then
      total = total + math.max(0, cell.elapsed)
      count = count + 1
    end
  end
  if count == 0 then return nil, 0 end
  return total, count
end

function Format.to_markdown(notebook)
  local lines = { "# " .. notebook:title(), "" }
  for _, cell in ipairs(notebook.cells) do
    if cell.kind == "markdown" then
      lines[#lines + 1] = cell.source or ""
      lines[#lines + 1] = ""
    else
      lines[#lines + 1] = "```lua"
      lines[#lines + 1] = cell.source or ""
      lines[#lines + 1] = "```"
      if cell.scene then
        lines[#lines + 1] = "> scene: " ..
          (type(cell.scene) == "table" and (cell.scene.type or "luaplotlib") or
            tostring(cell.scene))
      end
      if cell.error then
        lines[#lines + 1] = "> error: " .. tostring(cell.error)
      elseif cell.output and cell.output ~= "" then
        for line in (cell.output .. "\n"):gmatch("(.-)\n") do
          lines[#lines + 1] = "> " .. line
        end
      end
      lines[#lines + 1] = ""
    end
  end
  return table.concat(lines, "\n")
end

local function escape_html(value)
  return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;")
    :gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end

-- Markdown fenced blocks are not prose: tags and headings inside them must not
-- leak into the index or the exported table of contents.
local function prose_lines(source)
  local lines, fence = {}, nil
  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    local marker = line:match("^%s*([`~][`~][`~]+)")
    if fence ~= nil then
      if marker ~= nil and marker:sub(1, 1) == fence:sub(1, 1) and
         #marker >= #fence then
        fence = nil
      end
      lines[#lines + 1] = { text = "", fenced = true }
    elseif marker ~= nil then
      fence = marker
      lines[#lines + 1] = { text = "", fenced = true }
    else
      lines[#lines + 1] = { text = line, fenced = false }
    end
  end
  return lines
end

local function strip_inline_code(line)
  local out, index = {}, 1
  while index <= #line do
    local start = line:find("`", index, true)
    if start == nil then
      out[#out + 1] = line:sub(index)
      break
    end
    out[#out + 1] = line:sub(index, start - 1)
    local run = line:match("^`+", start)
    local closing = line:find(run, start + #run, true)
    if closing == nil then
      out[#out + 1] = line:sub(start)
      break
    end
    out[#out + 1] = " "
    index = closing + #run
  end
  return table.concat(out)
end

local function tag_boundary(previous)
  if previous == nil or previous == "" then return true end
  return previous:match("[%s%(%[{<\"'`%,;:>*]") ~= nil
end

local function tag_tokens(line)
  local tokens, position = {}, 1
  while true do
    local hash = line:find("#", position, true)
    if hash == nil then break end
    local tag = line:match("^#([%a_][%w_-]*)", hash)
    if tag ~= nil then
      local previous = hash > 1 and line:sub(hash - 1, hash - 1) or nil
      -- Three-to-eight digit hexadecimal tokens are colors, not tags.
      local color_like = tag:match("^[%x]+$") ~= nil and
        (#tag == 3 or #tag == 4 or #tag == 6 or #tag == 8)
      if tag_boundary(previous) and not color_like then
        tokens[#tokens + 1] = tag
      end
    end
    position = hash + 1
  end
  return tokens
end

function Format.tags(cells)
  local counts, order = {}, {}
  for _, cell in ipairs(cells or {}) do
    if cell.kind == "markdown" then
      for _, entry in ipairs(prose_lines(cell.source)) do
        if not entry.fenced then
          for _, tag in ipairs(tag_tokens(strip_inline_code(entry.text))) do
            if counts[tag] == nil then order[#order + 1] = tag end
            counts[tag] = (counts[tag] or 0) + 1
          end
        end
      end
    end
  end
  return counts, order
end

local function heading_text(raw)
  local text = raw:gsub("%s+#+%s*$", "")
  text = text:gsub("%*%*(.-)%*%*", "%1")
  text = text:gsub("`([^`]*)`", "%1")
  text = text:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  text = text:gsub("%[%[([^%]]+)%]%]", "%1")
  text = text:gsub("%*(.-)%*", "%1")
  return text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function slugify(text)
  local slug = text:lower():gsub("[^%w]+", "-")
    :gsub("^%-+", ""):gsub("%-+$", "")
  if slug == "" then slug = "section" end
  return slug
end

-- Deterministic heading outline with unique anchors.  Used by both the table
-- of contents and the markdown renderer so the links always resolve.
function Format.headings(cells)
  local result, used = {}, {}
  for cell_index, cell in ipairs(cells or {}) do
    if cell.kind == "markdown" then
      for _, entry in ipairs(prose_lines(cell.source)) do
        if not entry.fenced then
          local hashes, raw = entry.text:match("^%s*(#+)%s+(.+)$")
          if hashes ~= nil and #hashes <= 6 then
            local text = heading_text(raw)
            if text ~= "" then
              local base = slugify(text)
              local id, suffix = base, 1
              while used[id] do
                suffix = suffix + 1
                id = base .. "-" .. suffix
              end
              used[id] = true
              result[#result + 1] = {
                level = #hashes,
                text = text,
                id = id,
                cell = cell_index,
              }
            end
          end
        end
      end
    end
  end
  return result
end

local function headings_by_cell(cells)
  local result = {}
  for _, heading in ipairs(Format.headings(cells)) do
    result[heading.cell] = result[heading.cell] or {}
    result[heading.cell][#result[heading.cell] + 1] = heading
  end
  return result
end

-- Trim sentence punctuation from a bare URL without touching balanced closing
-- parentheses or an HTML entity's semicolon.  Returns the link and the suffix
-- so the punctuation stays outside the generated anchor.
local function trim_autolink(url)
  local trimmed = url
  while #trimmed > 0 do
    local last = trimmed:sub(-1)
    if last == "." or last == "," or last == ":" or last == "!" or
       last == "?" then
      trimmed = trimmed:sub(1, -2)
    elseif last == ";" then
      if trimmed:match("&[%a#][%w#]*;$") ~= nil then break end
      trimmed = trimmed:sub(1, -2)
    elseif last == ")" then
      local opens = select(2, trimmed:gsub("%(", ""))
      local closes = select(2, trimmed:gsub("%)", ""))
      if closes > opens then
        trimmed = trimmed:sub(1, -2)
      else
        break
      end
    else
      break
    end
  end
  return trimmed, url:sub(#trimmed + 1)
end

local function footnote_context(source, prefix)
  local context = {
    definitions = {},
    numbers = {},
    order = {},
    prefix = (prefix or "cell"):gsub("[^%w%-_]", "-"),
  }
  local in_fence = false
  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    if line:match("^%s*[`~][`~][`~]+") then
      in_fence = not in_fence
    elseif not in_fence then
      local label, body = line:match("^%s*%[%^([%w%-_]+)%]:%s*(.*)$")
      if label ~= nil and context.definitions[label] == nil then
        context.definitions[label] = body
      end
    end
  end
  return context
end

local function footnote_number(context, label)
  if context == nil or context.definitions[label] == nil then return nil end
  local number = context.numbers[label]
  if number == nil then
    number = #context.order + 1
    context.numbers[label] = number
    context.order[number] = label
  end
  return number
end

local function inline_markdown(text, footnotes)
  local escaped = escape_html(text)
  local slots = {}
  local function hold(html)
    slots[#slots + 1] = html
    return "\1" .. #slots .. "\1"
  end
  -- Backslash escapes are literal characters, so hide them before code and
  -- emphasis can claim the punctuation.
  escaped = escaped:gsub("\\([\\`*_~=%[%]()#+%.!|%-%%])", function(char)
    return hold(char)
  end)
  -- Inline code wins over emphasis and links; keep it in a placeholder until
  -- the rest of the inline pass has run.
  escaped = escaped:gsub("`([^`]*)`", function(code)
    return hold("<code>" .. code .. "</code>")
  end)
  escaped = escaped:gsub("%[%[([^%]]+)%]%]", function(target)
    return hold('<span class="wiki-link" data-target="' .. target .. '">' ..
      target .. "</span>")
  end)
  escaped = escaped:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(label, url)
    local lower = url:lower()
    local scheme = lower:match("^%s*([%a][%w+.-]*):")
    if scheme ~= nil and scheme ~= "http" and scheme ~= "https" and
       scheme ~= "mailto" then
      return label
    end
    local rel = (scheme == "http" or scheme == "https") and
      ' rel="noopener noreferrer"' or ""
    return hold('<a href="' .. url .. '"' .. rel .. ">" .. label .. "</a>")
  end)
  -- Bare http(s) links are common in notes.  Explicit links are already held,
  -- so their destinations and labels are not linked a second time.
  escaped = escaped:gsub("https?://[^%s]+", function(url)
    local link, trailing = trim_autolink(url)
    if link == "" then return url end
    return hold('<a href="' .. link ..
      '" rel="noopener noreferrer">' .. link .. "</a>") .. trailing
  end)
  escaped = escaped:gsub("==(.-)==", "<mark>%1</mark>")
  escaped = escaped:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
  escaped = escaped:gsub("__(.-)__", "<strong>%1</strong>")
  escaped = escaped:gsub("~~(.-)~~", "<del>%1</del>")
  escaped = escaped:gsub("%*(.-)%*", "<em>%1</em>")
  escaped = escaped:gsub("^_([^_]+)_", "<em>%1</em>")
  escaped = escaped:gsub("([^%w_])_([^_]+)_", "%1<em>%2</em>")
  if footnotes ~= nil then
    escaped = escaped:gsub("%[%^([%w%-_]+)%]", function(label)
      local number = footnote_number(footnotes, label)
      if number == nil then return "[^" .. label .. "]" end
      local reference = "fnref-" .. footnotes.prefix .. "-" .. number
      local target = "fn-" .. footnotes.prefix .. "-" .. number
      return '<sup class="footnote-ref" id="' .. reference .. '">' ..
        '<a href="#' .. target .. '">' .. number .. "</a></sup>"
    end)
  end
  -- A held anchor can contain an earlier code slot; restore until stable.
  while true do
    local restored, count = escaped:gsub("\1(%d+)\1", function(index)
      return slots[tonumber(index)] or ""
    end)
    escaped = restored
    if count == 0 then break end
  end
  return escaped
end

local function split_markdown_lines(source)
  local lines = {}
  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

-- Split a pipe table row without treating an escaped pipe as a cell boundary.
local function table_row(line)
  if line == nil or line:find("|", 1, true) == nil then return nil end
  local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed:sub(1, 1) == "|" then trimmed = trimmed:sub(2) end
  if trimmed:sub(-1) == "|" then trimmed = trimmed:sub(1, -2) end
  trimmed = trimmed:gsub("\\|", "\1")
  local cells = {}
  for cell in (trimmed .. "|"):gmatch("(.-)|") do
    cells[#cells + 1] = cell:gsub("\1", "|")
  end
  return cells
end

local function table_alignment(line)
  local cells = table_row(line)
  if cells == nil or #cells == 0 then return nil end
  local aligns = {}
  for _, cell in ipairs(cells) do
    local value = cell:gsub("%s+", "")
    if value:match("^:?%-+:?$") == nil then return nil end
    if value:sub(1, 1) == ":" and value:sub(-1) == ":" then
      aligns[#aligns + 1] = "center"
    elseif value:sub(-1) == ":" then
      aligns[#aligns + 1] = "right"
    else
      aligns[#aligns + 1] = "left"
    end
  end
  return aligns
end

local function table_cell_html(tag, value, alignment, footnotes)
  local class = alignment ~= "left" and (' class="align-' .. alignment .. '"') or ""
  return "<" .. tag .. class .. ">" ..
    inline_markdown(value:gsub("^%s+", ""):gsub("%s+$", ""), footnotes) ..
    "</" .. tag .. ">"
end

local function table_html(lines, index, header, aligns, footnotes)
  local count = #aligns
  local function row(cells, tag)
    local parts = {}
    for column = 1, count do
      parts[#parts + 1] = table_cell_html(tag, cells[column] or "",
        aligns[column], footnotes)
    end
    return "<tr>" .. table.concat(parts) .. "</tr>"
  end
  local html = { '<table class="markdown-table"><thead>', row(header, "th"),
    "</thead><tbody>" }
  local cursor = index + 2
  while cursor <= #lines do
    local line = lines[cursor]
    if line:match("^%s*$") then break end
    local cells = table_row(line)
    if cells == nil then break end
    html[#html + 1] = row(cells, "td")
    cursor = cursor + 1
  end
  html[#html + 1] = "</tbody></table>"
  return table.concat(html), cursor
end

local function list_indent(prefix)
  local width = 0
  for character in prefix:gmatch(".") do
    width = width + (character == "\t" and 2 or 1)
  end
  return width
end

local function list_item(line)
  local prefix, rest = line:match("^(%s*)(.*)$")
  local checked, task = rest:match("^[-*+]%s+%[([ xX])%]%s+(.*)$")
  if checked ~= nil then
    return { indent = list_indent(prefix), kind = "task", text = task,
      checked = checked:lower() == "x" }
  end
  local bullet = rest:match("^[-*+]%s+(.*)$")
  if bullet ~= nil then
    return { indent = list_indent(prefix), kind = "ul", text = bullet }
  end
  local number, item = rest:match("^(%d+)[%.%)]%s+(.*)$")
  if number ~= nil then
    return { indent = list_indent(prefix), kind = "ol", text = item,
      start = tonumber(number) or 1 }
  end
  return nil
end

local function safe_language(language)
  local label = tostring(language or ""):gsub("[^%w_+%-]", "")
  if label == "" then return "text" end
  return label
end

-- A self-contained code block with a language badge, CSS line numbers, and a
-- copy control that the inline script wires up when JavaScript is available.
local function code_block_html(source, language)
  local label = safe_language(language)
  local lines, count = {}, 0
  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    count = count + 1
    lines[#lines + 1] = string.format(
      '<span class="code-line" data-line="%d">%s</span>',
      count, escape_html(line))
  end
  if count == 0 then
    lines[1] = '<span class="code-line" data-line="1"></span>'
  end
  return '<div class="code-block">' ..
    '<div class="code-head"><span class="code-lang">' .. escape_html(label) ..
    '</span><button type="button" class="copy-code" aria-label="Copy ' ..
    escape_html(label) .. ' code">Copy</button></div>' ..
    '<pre class="source"><code class="language-' .. label .. '">' ..
    table.concat(lines) .. "</code></pre></div>"
end

local function quote_depth(line)
  local depth, rest = 0, line
  while true do
    local prefix, content = rest:match("^(%s*>%s?)(.*)$")
    if prefix == nil then break end
    depth = depth + 1
    rest = content
  end
  return depth, rest
end

local CALLOUT_TITLES = {
  note = "Note", tip = "Tip", important = "Important",
  warning = "Warning", caution = "Caution",
}

local function callout_marker(entry)
  if entry == nil or entry.depth ~= 1 then return nil end
  local kind, rest = entry.text:match("^%s*%[!(%a+)%]%s*(.*)$")
  if kind == nil then return nil end
  kind = kind:lower()
  if CALLOUT_TITLES[kind] == nil then return nil end
  return kind, rest
end

-- Render consecutive blockquote entries as nested <blockquote> blocks while
-- keeping one paragraph per source line, matching the existing preview/export
-- behavior for depth-one quotes.  A leading `[!NOTE]`-style marker becomes a
-- callout instead of a plain quote.
local function quote_html(entries, footnotes)
  local function render_from(list, start, depth)
    local out = {}
    local index = start
    while index <= #list and list[index].depth >= depth do
      if list[index].depth == depth then
        if list[index].text ~= "" then
          out[#out + 1] = "<p>" ..
            inline_markdown(list[index].text, footnotes) .. "</p>"
        end
        index = index + 1
      else
        local child_start = index
        while index <= #list and list[index].depth > depth do
          index = index + 1
        end
        out[#out + 1] = "<blockquote>" ..
          render_from(list, child_start, depth + 1) .. "</blockquote>"
      end
    end
    return table.concat(out)
  end

  local kind, rest = callout_marker(entries[1])
  if kind ~= nil then
    local body = {}
    if rest ~= "" then body[#body + 1] = { depth = 1, text = rest } end
    for index = 2, #entries do body[#body + 1] = entries[index] end
    return '<div class="callout callout-' .. kind .. '">' ..
      '<p class="callout-title">' .. CALLOUT_TITLES[kind] .. "</p>" ..
      render_from(body, 1, 1) .. "</div>"
  end
  return "<blockquote>" .. render_from(entries, 1, 1) .. "</blockquote>"
end

-- A term line followed by `: definition` lines becomes a description list.
-- Marker-heavy lines are left to the normal block parser.
local function definition_list_html(lines, index, footnotes)
  local items = {}
  local cursor = index
  while cursor <= #lines do
    local term = lines[cursor]
    local definition = lines[cursor + 1] and
      lines[cursor + 1]:match("^%s*:%s+(.*)$")
    if definition == nil or term:match("^%s*$") or
       term:match("^%s*[#%->:]") then
      break
    end
    local clean = term:gsub("^%s+", ""):gsub("%s+$", "")
    items[#items + 1] = "<dt>" .. inline_markdown(clean, footnotes) ..
      "</dt><dd>" .. inline_markdown(definition, footnotes) .. "</dd>"
    cursor = cursor + 2
  end
  return "<dl>" .. table.concat(items) .. "</dl>", cursor
end

-- Small, readable Markdown renderer for static exports.  It intentionally
-- covers the subset the editor previews: headings, nested lists, pipe tables,
-- quotes, fenced code, emphasis, inline code, links, and wiki links.
local function markdown_html(source, headings, footnote_prefix)
  local lines = split_markdown_lines(source)
  local footnotes = footnote_context(source, footnote_prefix)
  local out = {}
  local fence, fence_language, fence_lines = nil, nil, {}
  local paragraph, quote = {}, {}
  local list_stack = {}
  local heading_index = 0

  local function flush_paragraph()
    if #paragraph > 0 then
      out[#out + 1] = "<p>" .. table.concat(paragraph, "\n") .. "</p>"
      paragraph = {}
    end
  end

  local function render_list(entry)
    local tag = entry.kind == "ol" and "ol" or "ul"
    local attributes = ""
    if entry.kind == "task" then
      attributes = ' class="task-list"'
    elseif entry.kind == "ol" and entry.start ~= 1 then
      attributes = ' start="' .. tostring(entry.start) .. '"'
    end
    local items = {}
    for _, item in ipairs(entry.items) do
      local body
      if entry.kind == "task" then
        body = '<li class="task-list-item' ..
          (item.checked and " done" or "") .. '">' ..
          '<input type="checkbox" disabled' ..
          (item.checked and " checked" or "") .. "> " ..
          inline_markdown(item.text, footnotes)
      else
        body = "<li>" .. inline_markdown(item.text, footnotes)
      end
      for _, child in ipairs(item.children or {}) do
        body = body .. child
      end
      items[#items + 1] = body .. "</li>"
    end
    return "<" .. tag .. attributes .. ">" .. table.concat(items) ..
      "</" .. tag .. ">"
  end

  local function close_list()
    local entry = table.remove(list_stack)
    if entry == nil then return end
    local html = render_list(entry)
    local parent = list_stack[#list_stack]
    if parent ~= nil then
      local item = parent.items[#parent.items]
      if item ~= nil then item.children[#item.children + 1] = html end
    else
      out[#out + 1] = html
    end
  end

  local function close_lists()
    while #list_stack > 0 do close_list() end
  end

  local function add_list_item(item)
    while #list_stack > 0 and item.indent < list_stack[#list_stack].indent do
      close_list()
    end
    local top = list_stack[#list_stack]
    if top ~= nil and top.indent == item.indent and top.kind ~= item.kind then
      close_list()
      top = list_stack[#list_stack]
    end
    if top == nil or top.indent < item.indent then
      top = { kind = item.kind, indent = item.indent,
        start = item.start or 1, items = {} }
      list_stack[#list_stack + 1] = top
    end
    top.items[#top.items + 1] = { text = item.text,
      checked = item.checked == true, children = {} }
  end

  local function flush_quote()
    if #quote > 0 then
      out[#out + 1] = quote_html(quote, footnotes)
      quote = {}
    end
  end

  local function flush_blocks()
    flush_paragraph()
    close_lists()
    flush_quote()
  end

  local function flush_fence()
    if fence ~= nil then
      out[#out + 1] = code_block_html(table.concat(fence_lines, "\n"),
        fence_language)
      fence, fence_language, fence_lines = nil, nil, {}
    end
  end

  local function append_footnotes()
    if #footnotes.order == 0 then return end
    local items = {}
    for number, label in ipairs(footnotes.order) do
      local id = "fn-" .. footnotes.prefix .. "-" .. number
      local reference = "fnref-" .. footnotes.prefix .. "-" .. number
      items[#items + 1] = '<li id="' .. id .. '">' ..
        inline_markdown(footnotes.definitions[label] or "", footnotes) ..
        ' <a class="footnote-back" href="#' .. reference ..
        '" aria-label="Back to footnote ' .. number .. '">↩</a></li>'
    end
    out[#out + 1] = '<section class="footnotes" role="doc-endnotes">' ..
      "<hr><ol>" .. table.concat(items) .. "</ol></section>"
  end

  local index = 1
  while index <= #lines do
    local line = lines[index]
    local marker, language = line:match(
      "^%s*([`~][`~][`~]+)%s*([%w_+%-]*)%s*$")
    if fence ~= nil then
      if marker ~= nil and marker:sub(1, 1) == fence:sub(1, 1) and
         #marker >= #fence then
        flush_fence()
      else
        fence_lines[#fence_lines + 1] = line
      end
      index = index + 1
    elseif marker ~= nil then
      flush_blocks()
      fence, fence_language = marker, language or ""
      index = index + 1
    else
      local definition = line:match("^%s*%[%^([%w%-_]+)%]:")
      if definition ~= nil then
        -- Definitions are rendered as the endnotes section below.
        flush_blocks()
        index = index + 1
      else
        local next_definition = lines[index + 1] and
          lines[index + 1]:match("^%s*:%s+")
        if next_definition ~= nil and not line:match("^%s*$") and
           not line:match("^%s*[#%->:]") then
          flush_blocks()
          local html, next_index = definition_list_html(lines, index,
            footnotes)
          out[#out + 1] = html
          index = next_index
        else
        local header = table_row(line)
        local aligns = header and table_alignment(lines[index + 1] or "")
        if header ~= nil and aligns ~= nil then
          flush_blocks()
          local html, next_index = table_html(lines, index, header, aligns,
            footnotes)
          out[#out + 1] = html
          index = next_index
        else
          local item = list_item(line)
          local hashes, raw = line:match("^%s*(#+)%s+(.+)$")
          if hashes ~= nil and #hashes <= 6 then
            flush_blocks()
            heading_index = heading_index + 1
            local heading = headings and headings[heading_index] or nil
            local id = heading and
              (' id="' .. escape_html(heading.id) .. '"') or ""
            local permalink = ""
            if heading ~= nil then
              permalink = '<a class="heading-permalink" href="#' ..
                escape_html(heading.id) .. '" aria-label="Permalink to ' ..
                escape_html(heading.text) .. '">#</a>'
            end
            out[#out + 1] = "<h" .. #hashes .. id .. ">" ..
              inline_markdown(raw:gsub("%s+#+%s*$", ""), footnotes) ..
              permalink .. "</h" .. #hashes .. ">"
          elseif line:match("^%s*([%*%-_])%s*%1%s*%1[%s%*%-_]*$") then
            flush_blocks()
            out[#out + 1] = "<hr>"
          elseif item ~= nil then
            flush_paragraph(); flush_quote()
            add_list_item(item)
          elseif line:match("^%s*>%s?") then
            flush_paragraph(); close_lists()
            local depth, text = quote_depth(line)
          quote[#quote + 1] = { depth = depth, text = text }
          elseif line:match("^%s*$") then
            flush_blocks()
          else
            close_lists(); flush_quote()
            paragraph[#paragraph + 1] =
              inline_markdown(line:gsub("^%s+", ""), footnotes)
          end
          index = index + 1
        end
        end
      end
    end
  end
  flush_fence(); flush_blocks()
  append_footnotes()
  return table.concat(out, "\n")
end

function Format.wiki_links(cells)
  local links, seen = {}, {}
  for _, cell in ipairs(cells or {}) do
    for title in (cell.source or ""):gmatch("%[%[([^%]]+)%]%]") do
      if not seen[title] then seen[title] = true; links[#links + 1] = title end
    end
  end
  return links
end

function Format.backlinks(notebooks, title)
  local result = {}
  for _, notebook in ipairs(notebooks or {}) do
    if notebook:title() ~= title then
      for _, cell in ipairs(notebook.cells) do
        if (cell.source or ""):find("[[" .. title .. "]]", 1, true) then
          result[#result + 1] = notebook:title(); break
        end
      end
    end
  end
  return result
end

local function valid_color(value)
  if type(value) ~= "string" then return nil end
  if value:match("^#%x%x%x%x%x%x$") or value:match("^#%x%x%x$") then
    return value
  end
  return nil
end

local SCENE_PALETTE = {
  "#4c78a8", "#f58518", "#54a24b", "#b279a2", "#e45756", "#72b7b2",
}

local function finite_number(value)
  return type(value) == "number" and value == value and
    value ~= math.huge and value ~= -math.huge
end

-- Renderer-agnostic description of a scene output.  Kept separate from the SVG
-- so the figure caption, the table of contents, and tests share one summary.
function Format.scene_summary(scene)
  if type(scene) == "string" then
    return { kind = "extension", type = scene, title = nil,
      series = {}, count = 0, points = 0 }
  end
  if type(scene) ~= "table" then return nil end
  local scene_type = type(scene.type) == "string" and scene.type or "scene"
  if scene.orientation == "polar" then
    local polar = type(scene.polar) == "table" and scene.polar or {}
    local series, points = {}, 0
    -- Fields are painted first, then the data series; keep the summary in the
    -- same order so the caption and search index describe the drawing.
    for _, heatmap in ipairs(Polar.collect_heatmaps(polar)) do
      local count = heatmap.rows * heatmap.cols
      points = points + count
      series[#series + 1] = {
        kind = "heatmap", count = count, label = heatmap.label,
      }
    end
    for _, contour in ipairs(Polar.collect_contours(polar)) do
      local count = 0
      for _, level in ipairs(contour.levels) do
        count = count + #level.segments
      end
      points = points + count
      series[#series + 1] = {
        kind = "contour", count = count, label = contour.style.label,
      }
    end
    for _, item in ipairs(polar.series or {}) do
      if type(item) == "table" then
        local count = 0
        if item.kind == "streamplot" then
          -- Count the integrated polyline points, not the value-grid cells.
          for _, line in ipairs(type(item.lines) == "table" and item.lines or
              {}) do
            if type(line) == "table" then
              local line_theta = type(line.theta) == "table" and line.theta or
                {}
              local line_r = type(line.r) == "table" and line.r or {}
              count = count + math.min(#line_theta, #line_r)
            end
          end
        elseif type(item.theta) == "table" and type(item.r) == "table" then
          count = math.min(#item.theta, #item.r)
        end
        points = points + count
        series[#series + 1] = {
          kind = type(item.kind) == "string" and item.kind or "line",
          count = count,
          label = type(item.style) == "table" and item.style.label or nil,
        }
      end
    end
    return { kind = "luaplotlib", type = scene_type, orientation = "polar",
      title = scene.title, series = series, count = #series, points = points }
  end
  if scene_type == "luaplotlib" or type(scene.series) == "table" then
    local series, points = {}, 0
    for _, item in ipairs(scene.series or {}) do
      if type(item) == "table" then
        local count = 0
        if item.kind == "hist" then
          count = #(item.counts or {})
        elseif type(item.x) == "table" then
          count = #item.x
        end
        points = points + count
        series[#series + 1] = {
          kind = type(item.kind) == "string" and item.kind or "line",
          count = count,
          label = type(item.style) == "table" and item.style.label or nil,
        }
      end
    end
    return { kind = "luaplotlib", type = scene_type, title = scene.title,
      series = series, count = #series, points = points }
  end
  return { kind = "extension", type = scene_type, title = scene.title,
    series = {}, count = 0, points = 0 }
end

function Format.scene_json(scene, limit)
  local ok, text = pcall(json.encode, scene)
  if not ok or type(text) ~= "string" then return nil, false end
  limit = limit or 4000
  if #text > limit then
    return text:sub(1, limit) .. "…", true
  end
  return text, false
end

local function collect_plot_series(scene)
  local collected, palette_index = {}, 0
  for _, item in ipairs(scene.series or {}) do
    if type(item) == "table" then
      local color = type(item.style) == "table" and
        valid_color(item.style.color) or nil
      if color == nil then
        palette_index = palette_index + 1
        color = SCENE_PALETTE[(palette_index - 1) % #SCENE_PALETTE + 1]
      end
      if item.kind == "line" or item.kind == "scatter" then
        local x, y = item.x, item.y
        if type(x) == "table" and type(y) == "table" then
          local points = {}
          for index = 1, math.min(#x, #y) do
            if finite_number(x[index]) and finite_number(y[index]) then
              points[#points + 1] = { x[index], y[index] }
            end
          end
          if #points > 0 then
            collected[#collected + 1] = {
              kind = item.kind, points = points, color = color,
            }
          end
        end
      elseif item.kind == "bar" then
        local x, y = item.x, item.y
        local width = finite_number(item.width) and
          math.max(0.001, item.width) or 0.7
        if type(x) == "table" and type(y) == "table" then
          local bars = {}
          for index = 1, math.min(#x, #y) do
            if finite_number(x[index]) and finite_number(y[index]) then
              bars[#bars + 1] = { x = x[index], y = y[index], width = width }
            end
          end
          if #bars > 0 then
            collected[#collected + 1] = {
              kind = "bar", bars = bars, color = color,
            }
          end
        end
      elseif item.kind == "hist" then
        local edges, counts = item.edges, item.counts
        if type(edges) == "table" and type(counts) == "table" then
          local bars = {}
          for index = 1, math.min(#edges - 1, #counts) do
            if finite_number(edges[index]) and
               finite_number(edges[index + 1]) and
               finite_number(counts[index]) then
              bars[#bars + 1] = {
                x = (edges[index] + edges[index + 1]) / 2,
                y = counts[index],
                width = edges[index + 1] - edges[index],
              }
            end
          end
          if #bars > 0 then
            collected[#collected + 1] = {
              kind = "hist", bars = bars, color = color,
            }
          end
        end
      end
    end
  end
  return collected
end

local function plot_bounds(scene, collected)
  local xmin, xmax, ymin, ymax
  local function include(x, y)
    if xmin == nil or x < xmin then xmin = x end
    if xmax == nil or x > xmax then xmax = x end
    if ymin == nil or y < ymin then ymin = y end
    if ymax == nil or y > ymax then ymax = y end
  end
  for _, series in ipairs(collected) do
    if series.points ~= nil then
      for _, point in ipairs(series.points) do include(point[1], point[2]) end
    elseif series.bars ~= nil then
      for _, bar in ipairs(series.bars) do
        include(bar.x - bar.width / 2, 0)
        include(bar.x + bar.width / 2, bar.y)
      end
    end
  end
  if xmin == nil then return nil end
  if scene.xlim ~= nil and finite_number(scene.xlim[1]) and
     finite_number(scene.xlim[2]) and scene.xlim[1] < scene.xlim[2] then
    xmin, xmax = scene.xlim[1], scene.xlim[2]
  end
  if scene.ylim ~= nil and finite_number(scene.ylim[1]) and
     finite_number(scene.ylim[2]) and scene.ylim[1] < scene.ylim[2] then
    ymin, ymax = scene.ylim[1], scene.ylim[2]
  end
  if xmax == xmin then xmin, xmax = xmin - 1, xmax + 1 end
  if ymax == ymin then ymin, ymax = ymin - 1, ymax + 1 end
  local pad_x, pad_y = (xmax - xmin) * 0.05, (ymax - ymin) * 0.08
  return xmin - pad_x, xmax + pad_x, ymin - pad_y, ymax + pad_y
end

local function svg_number(value)
  if not finite_number(value) then return "0" end
  return string.format("%.2f", value)
end

-- Self-contained SVG preview for a scene.  It is a static sketch, not a raster
-- of the live renderer: line/scatter/bar/hist data is mapped into a compact
-- plot, while extension scenes get a recognizable glyph.
function Format.scene_svg(scene, width, height)
  local summary = Format.scene_summary(scene)
  if summary == nil then return nil end
  width = tonumber(width) or 480
  height = tonumber(height) or 240
  local label = summary.kind == "extension" and
    ("extension scene " .. tostring(summary.type)) or
    (summary.orientation == "polar" and
      string.format("polar luaplotlib scene with %d series and %d points",
        summary.count, summary.points) or
      string.format("luaplotlib scene with %d series and %d points",
        summary.count, summary.points))
  local out = { string.format(
    '<svg class="scene-svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="%s" xmlns="http://www.w3.org/2000/svg">',
    width, height, width, height, escape_html(label)) }
  out[#out + 1] = string.format(
    '<rect class="scene-bg" x="0.5" y="0.5" width="%d" height="%d" rx="10"/>',
    width - 1, height - 1)

  local left, top = 54, 22
  local right, bottom = width - 20, height - 30
  local plot_w, plot_h = math.max(1, right - left), math.max(1, bottom - top)

  if summary.kind == "extension" and summary.type == "cube" then
    local cx, cy = width / 2, height / 2 + 8
    local size = math.min(width, height) * 0.24
    local apex = svg_number
    out[#out + 1] = string.format(
      '<polygon points="%s,%s %s,%s %s,%s %s,%s" fill="var(--accent)" opacity=".20" stroke="var(--accent)" stroke-width="1.4"/>',
      apex(cx), apex(cy - size * 1.5),
      apex(cx + size * 1.5), apex(cy - size * 0.75),
      apex(cx), apex(cy), apex(cx - size * 1.5), apex(cy - size * 0.75))
    out[#out + 1] = string.format(
      '<polygon points="%s,%s %s,%s %s,%s %s,%s" fill="var(--accent)" opacity=".10" stroke="var(--accent)" stroke-width="1.4"/>',
      apex(cx - size * 1.5), apex(cy - size * 0.75),
      apex(cx), apex(cy), apex(cx), apex(cy + size * 1.5),
      apex(cx - size * 1.5), apex(cy + size * 0.75))
    out[#out + 1] = string.format(
      '<polygon points="%s,%s %s,%s %s,%s %s,%s" fill="var(--accent)" opacity=".14" stroke="var(--accent)" stroke-width="1.4"/>',
      apex(cx + size * 1.5), apex(cy - size * 0.75),
      apex(cx), apex(cy), apex(cx), apex(cy + size * 1.5),
      apex(cx + size * 1.5), apex(cy + size * 0.75))
  elseif summary.kind == "extension" and summary.type == "grid" then
    local center = width / 2
    for index = 0, 8 do
      local x = left + plot_w * index / 8
      out[#out + 1] = string.format(
        '<line class="scene-grid" x1="%s" y1="%s" x2="%s" y2="%s"/>',
        svg_number(center + (index - 4) * 10), svg_number(top),
        svg_number(x), svg_number(bottom))
    end
    for index = 0, 4 do
      local y = top + plot_h * index / 4
      out[#out + 1] = string.format(
        '<line class="scene-grid" x1="%s" y1="%s" x2="%s" y2="%s"/>',
        svg_number(left), svg_number(y), svg_number(right), svg_number(y))
    end
    out[#out + 1] = string.format(
      '<rect class="scene-frame" x="%s" y="%s" width="%s" height="%s" rx="4"/>',
      svg_number(left), svg_number(top), svg_number(plot_w),
      svg_number(plot_h))
  elseif summary.kind == "extension" then
    out[#out + 1] = string.format(
      '<rect class="scene-frame" x="%s" y="%s" width="%s" height="%s" rx="8"/>',
      svg_number(left), svg_number(top), svg_number(plot_w),
      svg_number(plot_h))
    local cx, cy = width / 2, height / 2
    out[#out + 1] = string.format(
      '<polygon points="%s,%s %s,%s %s,%s %s,%s" fill="var(--accent)" opacity=".18" stroke="var(--accent)" stroke-width="1.2"/>',
      svg_number(cx), svg_number(cy - 22),
      svg_number(cx + 26), svg_number(cy),
      svg_number(cx), svg_number(cy + 22),
      svg_number(cx - 26), svg_number(cy))
  elseif summary.orientation == "polar" then
    local resolved = Polar.resolve(scene)
    local polar = resolved.polar
    local rmax = resolved.rmax
    local theta_zero = resolved.theta_zero
    local direction = resolved.direction
    local has_colorbar = resolved.colorbar ~= nil
    local cx, cy, radius = Polar.frame_layout(left, top, right, bottom,
      has_colorbar)
    local function project(theta, value)
      return Polar.project(cx, cy, radius, rmax, theta_zero, direction,
        theta, value)
    end
    local function annular_path(cell, part)
      local start_angle, end_angle = part.start_angle, part.end_angle
      local span = math.abs(end_angle - start_angle)
      local large = span > math.pi and 1 or 0
      local sweep = end_angle < start_angle and 1 or 0
      local ox0 = cx + cell.outer_radius * math.cos(start_angle)
      local oy0 = cy - cell.outer_radius * math.sin(start_angle)
      local ox1 = cx + cell.outer_radius * math.cos(end_angle)
      local oy1 = cy - cell.outer_radius * math.sin(end_angle)
      if cell.inner_radius <= 0.0005 then
        return string.format(
          "M %s %s L %s %s A %s %s 0 %d %d %s %s Z",
          svg_number(cx), svg_number(cy), svg_number(ox0),
          svg_number(oy0), svg_number(cell.outer_radius),
          svg_number(cell.outer_radius), large, sweep, svg_number(ox1),
          svg_number(oy1))
      end
      local ix0 = cx + cell.inner_radius * math.cos(start_angle)
      local iy0 = cy - cell.inner_radius * math.sin(start_angle)
      local ix1 = cx + cell.inner_radius * math.cos(end_angle)
      local iy1 = cy - cell.inner_radius * math.sin(end_angle)
      return string.format(
        "M %s %s A %s %s 0 %d %d %s %s L %s %s A %s %s 0 %d %d %s %s Z",
        svg_number(ox0), svg_number(oy0), svg_number(cell.outer_radius),
        svg_number(cell.outer_radius), large, sweep, svg_number(ox1),
        svg_number(oy1), svg_number(ix1), svg_number(iy1),
        svg_number(cell.inner_radius), svg_number(cell.inner_radius), large,
        1 - sweep, svg_number(ix0), svg_number(iy0))
    end
    local direction_label = polar.theta_direction == "clockwise" and
      "clockwise" or "counterclockwise"
    local has_streamplot = false
    for _, series in ipairs(resolved.series) do
      if series.kind == "streamplot" then
        has_streamplot = true
        break
      end
    end
    local stream_clip_id
    if has_streamplot then
      -- Clip the streamplot group as well as its centre lines: the browser
      -- applies the same circular clip so stroke caps and joins never spill
      -- past the frame.  The id is derived from the frame geometry, so two
      -- identical frames may share it harmlessly.
      stream_clip_id = string.format("scene-polar-clip-%s-%s-%s",
        svg_number(cx), svg_number(cy), svg_number(radius))
      stream_clip_id = stream_clip_id:gsub("[^%w_-]", "_")
      out[#out + 1] = string.format(
        '<defs><clipPath id="%s"><circle cx="%s" cy="%s" r="%s"/></clipPath></defs>',
        stream_clip_id, svg_number(cx), svg_number(cy), svg_number(radius))
    end
    out[#out + 1] = string.format(
      '<g class="scene-polar" data-polar="true" data-rmax="%s" data-theta-zero="%s" data-theta-direction="%s" data-has-colorbar="%s">',
      svg_number(rmax), svg_number(theta_zero),
      escape_html(direction_label), has_colorbar and "true" or "false")
    if scene.grid ~= false then
      for _, tick in ipairs(Polar.rings(polar, rmax)) do
        local ring_radius = radius * tick.value / rmax
        out[#out + 1] = string.format(
          '<circle class="scene-polar-ring" cx="%s" cy="%s" r="%s"/>',
          svg_number(cx), svg_number(cy), svg_number(ring_radius))
        local label = Polar.radius_label(tick)
        if label ~= nil then
          local label_x, label_y = Polar.ring_label_position(cx, cy,
            ring_radius)
          out[#out + 1] = string.format(
            '<text class="scene-polar-label" text-anchor="end" x="%s" y="%s">%s</text>',
            svg_number(label_x), svg_number(label_y), escape_html(label))
        end
      end
      for _, tick in ipairs(Polar.spokes(polar)) do
        local angle = theta_zero + direction * tick.value
        local x2 = cx + radius * math.cos(angle)
        local y2 = cy - radius * math.sin(angle)
        out[#out + 1] = string.format(
          '<line class="scene-polar-spoke" x1="%s" y1="%s" x2="%s" y2="%s"/>',
          svg_number(cx), svg_number(cy), svg_number(x2), svg_number(y2))
        local label = Polar.theta_label(tick)
        if label ~= nil then
          local label_x, label_y = Polar.theta_label_position(cx, cy,
            radius, angle)
          out[#out + 1] = string.format(
            '<text class="scene-polar-label" text-anchor="middle" x="%s" y="%s">%s</text>',
            svg_number(label_x), svg_number(label_y), escape_html(label))
        end
      end
    end

    -- Heatmaps and contours sit under the frame and the data series.  Large
    -- fields are sampled by the shared polar module; the group records the
    -- source grid and strides so a reader can see that cells are blocks.
    for _, heatmap in ipairs(resolved.heatmaps) do
      out[#out + 1] = string.format(
        '<g class="scene-polar-heatmap" data-rows="%d" data-cols="%d" data-row-step="%d" data-col-step="%d" data-sampled="%s">',
        heatmap.rows, heatmap.cols, heatmap.row_step or 1,
        heatmap.col_step or 1, heatmap.sampled and "true" or "false")
      for _, cell in ipairs(Polar.heatmap_cells(heatmap, cx, cy, radius,
          rmax, theta_zero, direction)) do
        local opacity = cell.alpha < 1 and string.format(
          ' fill-opacity="%s"', svg_number(cell.alpha)) or ""
        local spans = (cell.row_span > 1 or cell.col_span > 1) and
          string.format(' data-row-span="%d" data-col-span="%d"',
            cell.row_span, cell.col_span) or ""
        out[#out + 1] = string.format(
          '<g class="scene-polar-heatmap-cell" data-row="%d" data-col="%d"%s fill="%s"%s>',
          cell.row, cell.col, spans, cell.color, opacity)
        if cell.full_disc then
          out[#out + 1] = string.format(
            '<circle cx="%s" cy="%s" r="%s"/>', svg_number(cx),
            svg_number(cy), svg_number(cell.outer_radius))
        else
          for _, part in ipairs(cell.parts) do
            out[#out + 1] = string.format(
              '<path d="%s"/>', annular_path(cell, part))
          end
        end
        out[#out + 1] = "</g>"
      end
      out[#out + 1] = "</g>"
    end
    for _, contour in ipairs(resolved.contours) do
      local dash = ""
      if contour.style.linestyle == "dashed" then
        dash = ' stroke-dasharray="6 4"'
      elseif contour.style.linestyle == "dotted" then
        dash = ' stroke-dasharray="1.5 3"'
      end
      local opacity = contour.style.alpha < 1 and string.format(
        ' stroke-opacity="%s"', svg_number(contour.style.alpha)) or ""
      for _, level in ipairs(contour.levels) do
        local level_label = Polar.compact_number(level.level) or ""
        for _, segment in ipairs(level.segments) do
          local points = Polar.contour_segment_points(contour, segment, cx,
            cy, radius, rmax, theta_zero, direction)
          local path_parts = {}
          for index, point in ipairs(points) do
            path_parts[index] = svg_number(point[1]) .. " " ..
              svg_number(point[2])
          end
          if #path_parts > 0 then
            out[#out + 1] = string.format(
              '<path class="scene-polar-contour" fill="none" data-level="%s" d="M %s"%s stroke="%s" stroke-width="%s"%s/>',
              escape_html(level_label), table.concat(path_parts, " L "),
              dash, contour.style.color,
              svg_number(contour.style.linewidth), opacity)
          end
        end
        local label = Polar.contour_label(contour, level, cx, cy, radius,
          rmax, theta_zero, direction)
        if label ~= nil then
          out[#out + 1] = string.format(
            '<text class="scene-polar-contour-label" text-anchor="middle" x="%s" y="%s" font-size="10" fill="%s">%s</text>',
            svg_number(label.x), svg_number(label.y + 3),
            contour.style.color, escape_html(label.text))
        end
      end
    end

    out[#out + 1] = string.format(
      '<circle class="scene-polar-frame" cx="%s" cy="%s" r="%s"/>',
      svg_number(cx), svg_number(cy), svg_number(radius))
    for _, series in ipairs(resolved.series) do
      if series.points ~= nil then
        if series.kind == "line" then
          local step = Polar.sample_step(#series.points,
            Polar.LINE_SAMPLE_LIMIT)
          local points = {}
          for index = 1, #series.points, step do
            local point = series.points[index]
            local x, y = project(point.theta, point.r)
            points[#points + 1] = svg_number(x) .. "," .. svg_number(y)
          end
          out[#out + 1] = string.format(
            '<polyline class="scene-series scene-polar-line" points="%s" stroke="%s"/>',
            table.concat(points, " "), series.color)
        else
          local step = Polar.sample_step(#series.points,
            Polar.SCATTER_SAMPLE_LIMIT)
          for index = 1, #series.points, step do
            local point = series.points[index]
            local x, y = project(point.theta, point.r)
            out[#out + 1] = string.format(
              '<circle class="scene-point scene-polar-point" cx="%s" cy="%s" r="%s" fill="%s"/>',
              svg_number(x), svg_number(y),
              svg_number(Polar.point_radius(point)),
              point.color or series.color)
          end
        end
      elseif series.bars ~= nil then
        local step = Polar.sample_step(#series.bars, Polar.BAR_SAMPLE_LIMIT)
        for index = 1, #series.bars, step do
          local bar = series.bars[index]
          for _, sector in ipairs(Polar.bar_sectors(bar, radius, rmax,
              theta_zero, direction)) do
            local fill = sector.color or series.color
            if sector.full then
              out[#out + 1] = string.format(
                '<circle class="scene-polar-bar" cx="%s" cy="%s" r="%s" fill="%s"/>',
                svg_number(cx), svg_number(cy), svg_number(sector.radius),
                fill)
            else
              local start_angle, end_angle =
                sector.start_angle, sector.end_angle
              local x0 = cx + sector.radius * math.cos(start_angle)
              local y0 = cy - sector.radius * math.sin(start_angle)
              local x1 = cx + sector.radius * math.cos(end_angle)
              local y1 = cy - sector.radius * math.sin(end_angle)
              local large, sweep = Polar.arc_flags(sector)
              out[#out + 1] = string.format(
                '<path class="scene-polar-bar" d="M %s %s L %s %s A %s %s 0 %d %d %s %s Z" fill="%s"/>',
                svg_number(cx), svg_number(cy), svg_number(x0),
                svg_number(y0), svg_number(sector.radius),
                svg_number(sector.radius), large, sweep, svg_number(x1),
                svg_number(y1), fill)
            end
          end
        end
      elseif series.arrows ~= nil and series.lines == nil then
        local stroke_opacity, fill_opacity = "", ""
        if series.alpha < 1 then
          local alpha = svg_number(series.alpha)
          stroke_opacity = string.format(' stroke-opacity="%s"', alpha)
          fill_opacity = string.format(' fill-opacity="%s"', alpha)
        end
        out[#out + 1] = string.format(
          '<g class="scene-polar-quiver" data-count="%d" data-drawn="%d" data-stride="%d" data-max-arrows="%d" data-scale="%s" data-scale-mode="%s" data-pivot="%s" data-normalize="%s" data-color="%s">',
          series.count, series.drawn, series.stride, series.max_arrows,
          svg_number(series.scale),
          series.auto_scale and "auto" or "explicit", series.pivot,
          series.normalize and "true" or "false", series.color)
        for _, arrow in ipairs(Polar.quiver_arrows(series, cx, cy, radius,
            rmax, theta_zero, direction)) do
          out[#out + 1] = string.format(
            '<g class="scene-polar-quiver-arrow" data-index="%d" data-magnitude="%s" data-theta="%s" data-r="%s" data-angle="%s">',
            arrow.index, svg_number(arrow.magnitude),
            svg_number(arrow.theta), svg_number(arrow.r),
            svg_number(arrow.angle))
          if arrow.shaft then
            out[#out + 1] = string.format(
              '<line class="scene-polar-quiver-shaft" x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s" stroke-linecap="round"%s/>',
              svg_number(arrow.tail_x), svg_number(arrow.tail_y),
              svg_number(arrow.neck_x), svg_number(arrow.neck_y),
              series.color, svg_number(series.linewidth), stroke_opacity)
          end
          if arrow.headed then
            out[#out + 1] = string.format(
              '<polygon class="scene-polar-quiver-head" points="%s,%s %s,%s %s,%s" fill="%s"%s/>',
              svg_number(arrow.head_x1), svg_number(arrow.head_y1),
              svg_number(arrow.head_x2), svg_number(arrow.head_y2),
              svg_number(arrow.head_x3), svg_number(arrow.head_y3),
              series.color, fill_opacity)
          end
          out[#out + 1] = "</g>"
        end
        out[#out + 1] = "</g>"
      elseif series.lines ~= nil then
        local stroke_opacity, fill_opacity = "", ""
        if series.alpha < 1 then
          local alpha = svg_number(series.alpha)
          stroke_opacity = string.format(' stroke-opacity="%s"', alpha)
          fill_opacity = string.format(' fill-opacity="%s"', alpha)
        end
        local dash = ""
        if series.linestyle == "dashed" then
          dash = ' stroke-dasharray="6 4"'
        elseif series.linestyle == "dotted" then
          dash = ' stroke-dasharray="1.5 3"'
        end
        local draw_paths = series.linewidth > 0 and series.linestyle ~= "none"
        local drawn = Polar.stream_lines(series, cx, cy, radius, rmax,
          theta_zero, direction)
        local visible_lines, visible_points, visible_runs = 0, 0, 0
        for _, line in ipairs(drawn) do
          visible_lines = visible_lines + 1
          visible_points = visible_points + #line.points
          visible_runs = visible_runs + #line.runs
        end
        local clip_attr = stream_clip_id ~= nil and
          string.format(' clip-path="url(#%s)"', stream_clip_id) or ""
        out[#out + 1] = string.format(
          '<g class="scene-polar-streamplot" data-cols="%d" data-rows="%d" data-lines="%d" data-points="%d" data-arrow-count="%d" data-step="%s" data-step-mode="%s" data-density="%s" data-max-steps="%d" data-max-lines="%d" data-max-points="%d" data-arrows="%s" data-head="%s" data-linestyle="%s" data-arrow-fraction="%s" data-closed-lines="%d" data-visible-lines="%d" data-visible-points="%d" data-visible-runs="%d" data-periodic="%s" data-truncated="%s" data-color="%s"%s>',
          series.cols, series.rows, series.line_count, series.point_count,
          series.arrow_count, svg_number(series.step), series.step_mode,
          svg_number(series.density), series.max_steps, series.max_lines,
          series.max_points, series.arrows and "true" or "false",
          svg_number(series.head), series.linestyle,
          svg_number(series.arrow_fraction), series.closed_lines or 0,
          visible_lines, visible_points, visible_runs,
          series.periodic and "true" or "false",
          series.truncated and "true" or "false", series.color, clip_attr)
        for _, line in ipairs(drawn) do
          out[#out + 1] = string.format(
            '<g class="scene-polar-streamline" data-index="%d" data-points="%d" data-runs="%d" data-arrows="%d" data-closed="%s" data-clipped="%s">',
            line.index, #line.points, #line.runs, #line.arrows,
            line.closed and "true" or "false",
            line.clipped and "true" or "false")
          if draw_paths then
            for _, run in ipairs(line.runs) do
              local commands = {}
              for point_index, point in ipairs(run) do
                commands[point_index] = string.format("%s %s %s",
                  point_index == 1 and "M" or "L", svg_number(point.x),
                  svg_number(point.y))
              end
              out[#out + 1] = string.format(
                '<path class="scene-polar-streamline-path" d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"%s%s/>',
                table.concat(commands, " "), series.color,
                svg_number(series.linewidth), dash, stroke_opacity)
            end
          end
          for _, arrow in ipairs(line.arrows) do
            local head_points = arrow.head_points
            if type(head_points) ~= "table" or #head_points < 6 then
              head_points = {
                arrow.head_x1, arrow.head_y1, arrow.head_x2, arrow.head_y2,
                arrow.head_x3, arrow.head_y3,
              }
            end
            local polygon = {}
            for point_index = 1, #head_points, 2 do
              polygon[#polygon + 1] = string.format("%s,%s",
                svg_number(head_points[point_index]),
                svg_number(head_points[point_index + 1]))
            end
            out[#out + 1] = string.format(
              '<polygon class="scene-polar-stream-arrow" data-index="%d" data-theta="%s" data-r="%s" data-angle="%s" data-clipped="%s" points="%s" fill="%s"%s/>',
              arrow.index, svg_number(arrow.theta), svg_number(arrow.r),
              svg_number(arrow.angle), arrow.clipped and "true" or "false",
              table.concat(polygon, " "), series.color, fill_opacity)
          end
          out[#out + 1] = "</g>"
        end
        out[#out + 1] = "</g>"
      end
    end

    if resolved.colorbar ~= nil then
      local bar = resolved.colorbar
      local bx, by, bw, bh = Polar.colorbar_layout(cx, cy, radius)
      out[#out + 1] = string.format(
        '<g class="scene-polar-colorbar" data-orientation="vertical" data-vmin="%s" data-vmax="%s" data-x="%s" data-y="%s" data-width="%s" data-height="%s">',
        svg_number(bar.vmin), svg_number(bar.vmax), svg_number(bx),
        svg_number(by), svg_number(bw), svg_number(bh))
      for _, step in ipairs(Polar.colorbar_steps(bar)) do
        local top = by + bh * step.y0
        out[#out + 1] = string.format(
          '<rect class="scene-polar-colorbar-step" x="%s" y="%s" width="%s" height="%s" fill="%s"/>',
          svg_number(bx), svg_number(top), svg_number(bw),
          svg_number(bh * (step.y1 - step.y0) + 0.5), step.color)
      end
      out[#out + 1] = string.format(
        '<rect class="scene-polar-colorbar-frame" fill="none" x="%s" y="%s" width="%s" height="%s"/>',
        svg_number(bx - 0.5), svg_number(by - 0.5),
        svg_number(bw + 1), svg_number(bh + 1))
      local max_label = 0
      for _, tick in ipairs(Polar.colorbar_ticks(bar)) do
        local tick_y = by + bh * (1 - tick.fraction)
        out[#out + 1] = string.format(
          '<line class="scene-polar-colorbar-tick" x1="%s" y1="%s" x2="%s" y2="%s"/>',
          svg_number(bx + bw), svg_number(tick_y),
          svg_number(bx + bw + 4), svg_number(tick_y))
        out[#out + 1] = string.format(
          '<text class="scene-polar-colorbar-label" x="%s" y="%s">%s</text>',
          svg_number(bx + bw + 8), svg_number(tick_y + 3.5),
          escape_html(tick.label))
        max_label = math.max(max_label, #tick.label * 5.5)
      end
      if bar.label ~= nil then
        local title_x = bx + bw + 8 + max_label + 14
        local title_y = by + bh / 2
        out[#out + 1] = string.format(
          '<text class="scene-polar-colorbar-title" x="%s" y="%s" text-anchor="middle" transform="rotate(-90 %s %s)">%s</text>',
          svg_number(title_x), svg_number(title_y), svg_number(title_x),
          svg_number(title_y), escape_html(bar.label))
      end
      out[#out + 1] = "</g>"
    end
    out[#out + 1] = "</g>"
  else
    local collected = collect_plot_series(scene)
    local xmin, xmax, ymin, ymax = plot_bounds(scene, collected)
    if xmin ~= nil then
      local function sx(value)
        return left + (value - xmin) / (xmax - xmin) * plot_w
      end
      local function sy(value)
        return top + plot_h -
          (value - ymin) / (ymax - ymin) * plot_h
      end
      if scene.grid ~= false then
        for index = 1, 4 do
          local x = left + plot_w * index / 5
          local y = top + plot_h * index / 5
          out[#out + 1] = string.format(
            '<line class="scene-grid" x1="%s" y1="%s" x2="%s" y2="%s"/>',
            svg_number(x), svg_number(top), svg_number(x),
            svg_number(bottom))
          out[#out + 1] = string.format(
            '<line class="scene-grid" x1="%s" y1="%s" x2="%s" y2="%s"/>',
            svg_number(left), svg_number(y), svg_number(right),
            svg_number(y))
        end
      end
      out[#out + 1] = string.format(
        '<line class="scene-axis" x1="%s" y1="%s" x2="%s" y2="%s"/>',
        svg_number(left), svg_number(top), svg_number(left),
        svg_number(bottom))
      out[#out + 1] = string.format(
        '<line class="scene-axis" x1="%s" y1="%s" x2="%s" y2="%s"/>',
        svg_number(left), svg_number(bottom), svg_number(right),
        svg_number(bottom))
      for _, series in ipairs(collected) do
        if series.points ~= nil then
          if series.kind == "line" then
            local step = math.max(1, math.ceil(#series.points / 800))
            local points = {}
            for index = 1, #series.points, step do
              local point = series.points[index]
              points[#points + 1] = svg_number(sx(point[1])) .. "," ..
                svg_number(sy(point[2]))
            end
            out[#out + 1] = string.format(
              '<polyline class="scene-series" points="%s" stroke="%s"/>',
              table.concat(points, " "), series.color)
          else
            local step = math.max(1, math.ceil(#series.points / 400))
            for index = 1, #series.points, step do
              local point = series.points[index]
              out[#out + 1] = string.format(
                '<circle class="scene-point" cx="%s" cy="%s" r="2.6" fill="%s"/>',
                svg_number(sx(point[1])), svg_number(sy(point[2])),
                series.color)
            end
          end
        elseif series.bars ~= nil then
          for _, bar in ipairs(series.bars) do
            local x0 = sx(bar.x - bar.width / 2)
            local x1 = sx(bar.x + bar.width / 2)
            local y0 = sy(0)
            local y1 = sy(bar.y)
            local bar_y = math.min(y0, y1)
            out[#out + 1] = string.format(
              '<rect class="scene-bar" x="%s" y="%s" width="%s" height="%s" fill="%s"/>',
              svg_number(x0), svg_number(bar_y),
              svg_number(math.max(1, x1 - x0)),
              svg_number(math.max(1, math.abs(y1 - y0))), series.color)
          end
        end
      end
    else
      out[#out + 1] = string.format(
        '<rect class="scene-frame" x="%s" y="%s" width="%s" height="%s" rx="8"/>',
        svg_number(left), svg_number(top), svg_number(plot_w),
        svg_number(plot_h))
      out[#out + 1] = string.format(
        '<line class="scene-frame" x1="%s" y1="%s" x2="%s" y2="%s"/>',
        svg_number(left), svg_number(bottom), svg_number(right),
        svg_number(top))
    end
  end
  out[#out + 1] = "</svg>"
  return table.concat(out, "\n")
end

function Format.widget_summary(cell)
  local result = {}
  for _, spec in ipairs(type(cell) == "table" and cell.widgets or {}) do
    if type(spec) == "table" then
      result[#result + 1] = {
        kind = type(spec.kind) == "string" and spec.kind or "widget",
        label = type(spec.label) == "string" and spec.label or
          (type(spec.text) == "string" and spec.text or nil),
      }
    end
  end
  return result
end

local function source_line_count(source)
  if type(source) ~= "string" or source == "" then return 0 end
  local count = 1
  for _ in source:gmatch("\n") do count = count + 1 end
  return count
end

function Format.html_stats(notebook)
  local stats = {
    cells = #notebook.cells,
    code = 0,
    markdown = 0,
    figures = 0,
    widgets = 0,
    words = 0,
    tags = 0,
    lines = 0,
    code_lines = 0,
    markdown_lines = 0,
    headings = 0,
    links = 0,
    errors = 0,
    outputs = 0,
  }
  for _, cell in ipairs(notebook.cells) do
    local lines = source_line_count(cell.source)
    stats.lines = stats.lines + lines
    if cell.kind == "markdown" then
      stats.markdown = stats.markdown + 1
      stats.markdown_lines = stats.markdown_lines + lines
      for _ in (cell.source or ""):gmatch("%S+") do
        stats.words = stats.words + 1
      end
    else
      stats.code = stats.code + 1
      stats.code_lines = stats.code_lines + lines
    end
    if cell.scene ~= nil then stats.figures = stats.figures + 1 end
    stats.widgets = stats.widgets + #Format.widget_summary(cell)
    if cell.error ~= nil and cell.error ~= "" then
      stats.errors = stats.errors + 1
    end
    if cell.output ~= nil and cell.output ~= "" then
      stats.outputs = stats.outputs + 1
    end
  end
  for _ in pairs(Format.tags(notebook.cells)) do
    stats.tags = stats.tags + 1
  end
  stats.headings = #Format.headings(notebook.cells)
  stats.links = #Format.wiki_links(notebook.cells)
  return stats
end

-- Searchable projection of Markdown prose: keep visible labels, drop link and
-- image destinations (they are not rendered as text), and neutralize schemes
-- the renderer refuses to emit so the index never carries them verbatim.
local function markdown_search_text(source)
  local text = source or ""
  text = text:gsub("!%[([^%]]*)%]%b()", "%1")
  text = text:gsub("%[([^%]]*)%]%b()", "%1")
  text = text:gsub("([Jj][Aa][Vv][Aa][Ss][Cc][Rr][Ii][Pp][Tt]):", "%1 ")
  text = text:gsub("([Vv][Bb][Ss][Cc][Rr][Ii][Pp][Tt]):", "%1 ")
  return text
end

local function search_join(parts)
  local text = table.concat(parts, " ")
  return text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Plain-text projection of a cell for the reader's client-side search.  Case
-- is preserved (the browser lowercases both sides) and whitespace is collapsed
-- so the value can live in one HTML attribute.
function Format.search_text(cell)
  if type(cell) ~= "table" then return "" end
  local parts = {}
  local function add(value)
    if type(value) == "string" and value ~= "" then
      parts[#parts + 1] = value
    end
  end
  if cell.kind == "markdown" then
    add(markdown_search_text(cell.source))
  else
    add(cell.source)
  end
  add(cell.output)
  add(cell.error)
  local summary = cell.scene ~= nil and Format.scene_summary(cell.scene) or nil
  if summary ~= nil then
    add(summary.type)
    add(summary.title)
    add(summary.orientation)
    for _, item in ipairs(summary.series) do
      add(item.kind)
      add(item.label)
    end
  end
  for _, widget in ipairs(Format.widget_summary(cell)) do
    add(widget.kind)
    add(widget.label)
  end
  return search_join(parts)
end

local function render_scene(scene, number)
  local summary = Format.scene_summary(scene)
  if summary == nil then return nil end
  local out = { string.format(
    '<figure class="scene" id="figure-%d" data-scene="%s"%s>', number,
    escape_html(summary.type or "scene"),
    summary.orientation == "polar" and ' data-orientation="polar"' or "") }
  local svg = Format.scene_svg(scene, 480, 240)
  if svg ~= nil then out[#out + 1] = svg end
  out[#out + 1] = '<figcaption><span class="figure-index">Figure ' ..
    number .. "</span>"
  if type(summary.title) == "string" and summary.title ~= "" then
    out[#out + 1] = "<strong>" .. escape_html(summary.title) .. "</strong>"
  end
  local label
  if summary.kind == "extension" then
    label = string.format("extension scene · %s", summary.type)
  else
    local kinds, seen = {}, {}
    for _, item in ipairs(summary.series) do
      if not seen[item.kind] then
        seen[item.kind] = true
        kinds[#kinds + 1] = item.kind
      end
    end
    label = string.format("%d series · %d points", summary.count,
      summary.points)
    if #kinds > 0 then label = table.concat(kinds, ", ") .. " · " .. label end
    if summary.orientation == "polar" then label = "polar · " .. label end
  end
  out[#out + 1] = '<span class="figure-meta">' .. escape_html(label) ..
    "</span>"
  out[#out + 1] = '<span class="figure-note">Static preview — run the ' ..
    "notebook in lua-notebooks for the live scene.</span></figcaption>"
  local data, truncated = Format.scene_json(scene)
  if data ~= nil then
    out[#out + 1] = "<details><summary>Scene data" ..
      (truncated and " (truncated)" or "") ..
      '</summary><pre class="scene-data">' .. escape_html(data) ..
      "</pre></details>"
  end
  out[#out + 1] = "</figure>"
  return table.concat(out, "\n")
end

local function render_widgets(cell)
  local widgets = Format.widget_summary(cell)
  if #widgets == 0 then return nil end
  local out = {
    '<div class="widget-placeholder">',
    "<strong>Interactive widgets are not included in the static export.</strong>",
    "<ul>",
  }
  for _, widget in ipairs(widgets) do
    local label = ""
    if widget.label ~= nil then
      label = " — " .. escape_html(widget.label)
    end
    out[#out + 1] = "<li>" .. escape_html(widget.kind) .. label .. "</li>"
  end
  out[#out + 1] = "</ul></div>"
  return table.concat(out, "\n")
end

local HTML_STYLE = [==[
:root{color-scheme:light dark;--bg:#fbfbfd;--fg:#1e2530;--muted:#5a6473;--card:#fff;--code:#f3f4f7;--output:#edf7f1;--error:#fff0f0;--border:#dde2ea;--accent:#2f6fed;--figure:#f7f8fb;--toc:#f4f6fa;--shadow:0 1px 2px rgba(20,30,50,.06)}
@media (prefers-color-scheme:dark){:root{--bg:#0e1117;--fg:#e7ebf3;--muted:#98a2b3;--card:#151a23;--code:#111722;--output:#10231a;--error:#2a1518;--border:#273142;--accent:#7aa7ff;--figure:#0b0f16;--toc:#131923;--shadow:none}}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif}
a{color:var(--accent)}
.skip{position:absolute;left:-999px;top:0;background:var(--card);padding:.6rem 1rem;z-index:10}
.skip:focus{left:1rem;top:1rem}
.document-header{max-width:1080px;margin:0 auto;padding:2.6rem 1.4rem 1rem}
.eyebrow{margin:0 0 .5rem;color:var(--muted);font-size:.8rem;letter-spacing:.08em;text-transform:uppercase}
h1{font-size:2.15rem;line-height:1.15;margin:0 0 .7rem}
.meta{color:var(--muted);font-size:.9rem;margin:0}
.search{display:none;gap:.55rem;align-items:center;flex-wrap:wrap;margin:1rem 0 0}
.js .search{display:flex}
.search-label{color:var(--muted);font-size:.8rem;letter-spacing:.06em;text-transform:uppercase}
.search input[type=search]{flex:1 1 240px;min-width:0;padding:.5rem .65rem;border:1px solid var(--border);border-radius:8px;background:var(--card);color:var(--fg);font:inherit}
.search input[type=search]:focus{outline:2px solid var(--accent);outline-offset:1px}
.search select{padding:.5rem .55rem;border:1px solid var(--border);border-radius:8px;background:var(--card);color:var(--fg);font:inherit}
.search-status{color:var(--muted);font-size:.85rem;margin:.45rem 0 0}
[hidden]{display:none!important}
.layout{display:grid;grid-template-columns:minmax(0,220px) minmax(0,1fr);gap:2.2rem;max-width:1080px;margin:0 auto;padding:1rem 1.4rem 3rem;align-items:start}
.toc{position:sticky;top:1rem;background:var(--toc);border:1px solid var(--border);border-radius:12px;padding:1rem;font-size:.9rem;max-height:calc(100vh - 2rem);overflow:auto}
.toc-title{font-weight:650;margin:0 0 .6rem}
.toc-section{margin:1rem 0 .4rem;color:var(--muted);font-size:.72rem;letter-spacing:.08em;text-transform:uppercase}
.toc a{display:block;color:var(--fg);text-decoration:none;padding:.12rem 0;border-radius:4px}
.toc a:hover{color:var(--accent)}
.toc-level-1{font-weight:600}
.toc-level-2{padding-left:.7rem}
.toc-level-3{padding-left:1.3rem}
.toc-level-4,.toc-level-5,.toc-level-6{padding-left:1.8rem}
.toc-empty{color:var(--muted);margin:.2rem 0}
main{min-width:0}
.cell{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1rem 1.15rem;margin:0 0 1.2rem;box-shadow:var(--shadow);scroll-margin-top:1rem}
.cell:target{border-color:var(--accent)}
.cell-head{display:flex;justify-content:space-between;gap:1rem;color:var(--muted);font-size:.72rem;letter-spacing:.06em;text-transform:uppercase;margin-bottom:.55rem}
.permalink{color:var(--muted);text-decoration:none}
.permalink:hover{color:var(--accent)}
pre{margin:.6rem 0;background:var(--code);border-radius:8px;padding:.85rem 1rem;overflow:auto;font:13px/1.55 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.code-block{margin:.6rem 0}
.code-block pre{margin:0;border-top-left-radius:0;border-top-right-radius:0}
.code-head{display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.3rem .65rem;background:var(--code);border:1px solid var(--border);border-bottom:0;border-radius:8px 8px 0 0;font:11px/1.4 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;color:var(--muted)}
.code-lang{letter-spacing:.08em;text-transform:uppercase}
.copy-code{display:none;border:1px solid var(--border);border-radius:5px;background:var(--card);color:var(--fg);font:inherit;padding:.16rem .45rem;cursor:pointer}
.copy-code:hover{border-color:var(--accent);color:var(--accent)}
.js .copy-code{display:inline-flex}
.code-line{display:block;position:relative;min-height:1.55em;padding-left:2.8rem}
.code-line::before{content:attr(data-line);position:absolute;left:0;width:2rem;text-align:right;color:var(--muted);opacity:.62;user-select:none}
pre.output{background:var(--output);border-left:4px solid #4d9b6a}
pre.error{background:var(--error);border-left:4px solid #c94b4b;color:#b42323}
@media (prefers-color-scheme:dark){pre.error{color:#ff9c9c}}
.cell blockquote{margin:.7rem 0;padding:.35rem 0 .35rem 1rem;border-left:3px solid var(--border);color:var(--muted)}
.cell hr{border:0;border-top:1px solid var(--border);margin:1.2rem 0}
.cell del{color:var(--muted)}
.cell mark{background:#ffe58a;color:#2a2100;border-radius:3px;padding:0 .12em}
@media (prefers-color-scheme:dark){.cell mark{background:#5c4a12;color:#ffe7a8}}
.cell h1,.cell h2,.cell h3,.cell h4,.cell h5,.cell h6{line-height:1.25;margin:1.1rem 0 .5rem}
.heading-permalink{opacity:0;margin-left:.4rem;font-size:.72em;font-weight:400;color:var(--muted);text-decoration:none}
.cell h1:hover .heading-permalink,.cell h2:hover .heading-permalink,.cell h3:hover .heading-permalink,.cell h4:hover .heading-permalink,.cell h5:hover .heading-permalink,.cell h6:hover .heading-permalink,.heading-permalink:focus{opacity:1;color:var(--accent)}
@media print{.heading-permalink{opacity:1}}
.cell h1{font-size:1.55rem}
.cell h2{font-size:1.3rem}
.cell h3{font-size:1.12rem}
.cell ul,.cell ol{margin:.5rem 0 .8rem;padding-left:1.4rem}
.task-list{list-style:none;padding-left:.2rem}
.task-list-item{display:flex;gap:.5rem;align-items:baseline}
.task-list-item input{margin:0;accent-color:var(--accent)}
.task-list-item.done{color:var(--muted)}
.cell .markdown-table{width:100%;border-collapse:collapse;margin:.7rem 0 1rem;font-size:.94rem}
.markdown-table th,.markdown-table td{border:1px solid var(--border);padding:.38rem .55rem;text-align:left;vertical-align:top}
.markdown-table th{background:var(--toc);font-weight:650}
.markdown-table .align-center{text-align:center}
.markdown-table .align-right{text-align:right}
.footnote-ref{font-size:.72em;line-height:0;vertical-align:super}
.footnote-ref a{text-decoration:none}
.footnotes{margin:1.3rem 0 0;padding-top:.55rem;border-top:1px solid var(--border);color:var(--muted);font-size:.9rem}
.footnotes ol{margin:.4rem 0 0;padding-left:1.4rem}
.footnotes li{margin:.18rem 0}
.footnote-back{text-decoration:none;margin-left:.3rem}
@media print{.footnote-back{display:none}}
.callout{margin:.8rem 0;padding:.65rem .9rem;border-left:4px solid var(--accent);border-radius:7px;background:var(--toc)}
.callout-title{margin:0 0 .3rem;font-size:.78rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase}
.callout p{margin:.25rem 0}
.callout-note{border-left-color:#4b8bf5}
.callout-tip{border-left-color:#3fa66a}
.callout-important{border-left-color:#9b6bdf}
.callout-warning{border-left-color:#d79a31}
.callout-caution{border-left-color:#d15b5b}
.cell dl{margin:.7rem 0 1rem}
.cell dt{font-weight:650;margin-top:.45rem}
.cell dd{margin:.12rem 0 .45rem 1.2rem;color:var(--muted)}
.scene{margin:1rem 0 0;padding:0}
.scene-svg{display:block;width:100%;height:auto;border:1px solid var(--border);border-radius:10px;background:var(--figure)}
.scene figcaption{color:var(--muted);font-size:.86rem;padding:.55rem .15rem 0;display:flex;flex-wrap:wrap;gap:.35rem .6rem;align-items:baseline}
.figure-index{font-weight:650;color:var(--fg)}
.figure-note{flex-basis:100%;font-size:.8rem}
.scene details{margin:.45rem 0 0;color:var(--muted);font-size:.86rem}
.scene summary{cursor:pointer}
pre.scene-data{max-height:18rem;font-size:12px}
.widget-placeholder{margin:.85rem 0 0;padding:.75rem .9rem;border:1px dashed var(--border);border-radius:10px;color:var(--muted);font-size:.9rem}
.widget-placeholder strong{color:var(--fg)}
.widget-placeholder ul{margin:.4rem 0 0;padding-left:1.3rem}
.backlinks{max-width:1080px;margin:0 auto;padding:1.2rem 1.4rem 2.5rem;border-top:1px solid var(--border);color:var(--muted);font-size:.9rem}
.footer{max-width:1080px;margin:0 auto;padding:0 1.4rem 3rem;color:var(--muted);font-size:.82rem}
.wiki-link{border-bottom:1px dotted var(--muted)}
.scene-bg{fill:var(--figure);stroke:var(--border)}
.scene-grid{stroke:var(--border);stroke-width:1}
.scene-axis{stroke:var(--muted);stroke-width:1.2}
.scene-frame{fill:none;stroke:var(--muted);stroke-width:1.2;stroke-dasharray:5 4}
.scene-series{fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.scene-bar{stroke:none;opacity:.88}
.scene-point{stroke:none}
.scene-polar-frame{fill:none;stroke:var(--muted);stroke-width:1.2}
.scene-polar-ring{fill:none;stroke:var(--border);stroke-width:1}
.scene-polar-spoke{stroke:var(--border);stroke-width:1}
.scene-polar-label{fill:var(--muted);font:9px/1 system-ui,-apple-system,"Segoe UI",sans-serif}
.scene-polar-line{fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.scene-polar-bar{stroke:none;opacity:.82}
.scene-polar-heatmap-cell{stroke:none}
.scene-polar-contour{fill:none;stroke-linecap:round;stroke-linejoin:round}
.scene-polar-quiver-shaft{stroke-linecap:round}
.scene-polar-quiver-head{stroke:none}
.scene-polar-streamline-path{fill:none;stroke-linecap:round;stroke-linejoin:round}
.scene-polar-stream-arrow{stroke:none}
.scene-polar-colorbar-frame{fill:none;stroke:var(--muted);stroke-width:1}
.scene-polar-colorbar-tick{stroke:var(--muted);stroke-width:1}
.scene-polar-colorbar-label{fill:var(--muted);font:9px/1 system-ui,-apple-system,"Segoe UI",sans-serif}
.scene-polar-colorbar-title{fill:var(--muted);font:10px/1 system-ui,-apple-system,"Segoe UI",sans-serif}
@media (max-width:760px){.layout{display:block;padding-top:0}.toc{position:static;max-height:none;margin-bottom:1.4rem}h1{font-size:1.7rem}.search input[type=search]{flex-basis:100%}}
@media print{:root{--bg:#fff;--fg:#000;--muted:#444;--card:#fff;--code:#f4f4f4;--output:#f4f4f4;--border:#ccc;--figure:#fff}.toc,.skip,.permalink,.search,.search-status,.copy-code{display:none!important}.layout{display:block;max-width:none;padding:0}.document-header{padding:0 0 1rem}.cell{box-shadow:none;break-inside:avoid;page-break-inside:avoid}a{color:#000;text-decoration:none}.scene details{display:none}.cell mark{background:#ffe58a;color:#000}}
]==]

local HTML_CODE_SCRIPT = [==[
(function(){
  var buttons = document.querySelectorAll('.copy-code');
  if (!buttons.length) return;
  function textFor(block) {
    var lines = block.querySelectorAll('code .code-line');
    if (lines.length) {
      var parts = [];
      for (var index = 0; index < lines.length; index++) {
        parts.push(lines[index].textContent);
      }
      return parts.join('\n');
    }
    var code = block.querySelector('code');
    return code ? code.textContent : '';
  }
  function flash(button) {
    var label = button.textContent;
    button.textContent = 'Copied';
    window.setTimeout(function(){ button.textContent = label; }, 1200);
  }
  function fallback(text, button) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try { document.execCommand('copy'); flash(button); } catch (error) {}
    document.body.removeChild(area);
  }
  for (var index = 0; index < buttons.length; index++) {
    buttons[index].addEventListener('click', function(){
      var block = this.closest('.code-block');
      if (!block) return;
      var text = textFor(block);
      var button = this;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function(){ flash(button); },
          function(){ fallback(text, button); });
      } else {
        fallback(text, button);
      }
    });
  }
})();
]==]

local HTML_SEARCH_SCRIPT = [==[
(function(){
  var input = document.getElementById('search-input');
  if (!input) return;
  var kindFilter = document.getElementById('search-kind');
  var status = document.getElementById('search-status');
  var cells = Array.prototype.slice.call(
    document.querySelectorAll('main .cell'));
  var tocLinks = Array.prototype.slice.call(
    document.querySelectorAll('.toc a[data-cell]'));
  var tocSections = Array.prototype.slice.call(
    document.querySelectorAll('.toc .toc-section'));
  function lower(value) { return (value || '').toLowerCase(); }
  function terms() {
    var raw = lower(input.value).split(/\s+/);
    var result = [];
    for (var index = 0; index < raw.length; index++) {
      if (raw[index] !== '') result.push(raw[index]);
    }
    return result;
  }
  function matchesCell(cell, query) {
    var haystack = lower(cell.getAttribute('data-search'));
    for (var index = 0; index < query.length; index++) {
      if (haystack.indexOf(query[index]) < 0) return false;
    }
    return true;
  }
  function matchesKind(cell, kind) {
    if (kind === 'code' || kind === 'markdown') {
      return cell.getAttribute('data-kind') === kind;
    }
    if (kind === 'figures') {
      return cell.getAttribute('data-has-scene') === 'true';
    }
    return true;
  }
  function apply() {
    var query = terms();
    var kind = kindFilter ? kindFilter.value : 'all';
    var active = query.length > 0 || kind !== 'all';
    var shown = 0;
    for (var index = 0; index < cells.length; index++) {
      var cell = cells[index];
      var visible = matchesKind(cell, kind) && matchesCell(cell, query);
      cell.hidden = !visible;
      if (visible) shown++;
    }
    for (var linkIndex = 0; linkIndex < tocLinks.length; linkIndex++) {
      var link = tocLinks[linkIndex];
      var target = document.getElementById(
        'cell-' + link.getAttribute('data-cell'));
      link.hidden = !(target && !target.hidden);
    }
    for (var sectionIndex = 0; sectionIndex < tocSections.length;
         sectionIndex++) {
      var section = tocSections[sectionIndex];
      var node = section.nextElementSibling;
      var any = false;
      while (node && !node.classList.contains('toc-section')) {
        if (node.tagName === 'A' && !node.hidden) any = true;
        node = node.nextElementSibling;
      }
      section.hidden = !any;
    }
    if (status) {
      status.hidden = !active;
      if (active) {
        status.textContent = shown === 0
          ? 'No cells match this search.'
          : 'Showing ' + shown + ' of ' + cells.length + ' cells.';
      } else {
        status.textContent = '';
      }
    }
  }
  try {
    var params = new URLSearchParams(window.location.search);
    var query = params.get('q');
    if (query) input.value = query;
    var kind = params.get('kind');
    if (kind === 'all' || kind === 'code' || kind === 'markdown' ||
        kind === 'figures') {
      kindFilter.value = kind;
    }
  } catch (error) {}
  input.addEventListener('input', apply);
  if (kindFilter) kindFilter.addEventListener('change', apply);
  input.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
      input.value = '';
      if (kindFilter) kindFilter.value = 'all';
      apply();
      input.blur();
    }
  });
  document.addEventListener('keydown', function(event) {
    if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey) {
      return;
    }
    var target = event.target;
    var tag = target && target.tagName;
    if (tag !== 'INPUT' && tag !== 'TEXTAREA' && tag !== 'SELECT') {
      event.preventDefault();
      input.focus();
      input.select();
    }
  });
  apply();
})();
]==]

function Format.to_html(notebook, backlinks, options)
  options = options or {}
  local headings = Format.headings(notebook.cells)
  local by_cell = headings_by_cell(notebook.cells)
  local stats = Format.html_stats(notebook)
  local title = notebook:title()
  local kernel = notebook.kernel or "lua"
  local description = string.format(
    "%s — %d cells, %d code, %d markdown, %d figure(s), kernel %s",
    title, stats.cells, stats.code, stats.markdown, stats.figures, kernel)
  local out = {
    "<!doctype html>",
    '<html lang="en" class="no-js">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<meta name="generator" content="lua-notebooks">',
    '<meta name="color-scheme" content="light dark">',
    '<meta name="description" content="' .. escape_html(description) .. '">',
    '<meta property="og:title" content="' .. escape_html(title) .. '">',
    '<meta property="og:description" content="' ..
      escape_html(description) .. '">',
    '<meta property="og:type" content="article">',
    "<title>" .. escape_html(title) .. "</title>",
    "<style>" .. HTML_STYLE .. "</style>",
    "<script>document.documentElement.className=\"js\";</script>",
    "</head>",
    "<body>",
    '<a class="skip" href="#content">Skip to content</a>',
    '<header class="document-header">',
    '<p class="eyebrow">lua-notebooks · ' .. escape_html(kernel) ..
      " kernel</p>",
    "<h1>" .. escape_html(title) .. "</h1>",
    '<p class="meta">' .. string.format(
      "%d cells · %d code · %d markdown · %d figure(s) · %d widget(s)",
      stats.cells, stats.code, stats.markdown, stats.figures,
      stats.widgets) .. "</p>",
    '<div class="search" role="search">',
    '<label class="search-label" for="search-input">Search</label>',
    '<input id="search-input" type="search" ' ..
      'placeholder="Search code, prose, and figures" autocomplete="off" ' ..
      'spellcheck="false">',
    '<select id="search-kind" aria-label="Filter by cell kind">',
    '<option value="all">All cells</option>',
    '<option value="code">Code cells</option>',
    '<option value="markdown">Markdown cells</option>',
    '<option value="figures">Figure cells</option>',
    "</select>",
    "</div>",
    '<p class="search-status" id="search-status" role="status" ' ..
      'aria-live="polite" hidden></p>',
    "</header>",
    '<div class="layout">',
  }

  if options.navigation ~= false then
    out[#out + 1] = '<nav class="toc" aria-label="Contents">'
    out[#out + 1] = '<p class="toc-title">Contents</p>'
    if #headings == 0 then
      out[#out + 1] = '<p class="toc-empty">No markdown headings. ' ..
        "Use the permalink on each cell.</p>"
    else
      for _, heading in ipairs(headings) do
        out[#out + 1] = string.format(
          '<a class="toc-entry toc-level-%d" href="#%s" data-cell="%d">%s</a>',
          heading.level, escape_html(heading.id), heading.cell,
          escape_html(heading.text))
      end
    end
    local figures = {}
    for index, cell in ipairs(notebook.cells) do
      if cell.scene ~= nil then
        figures[#figures + 1] = {
          index = index, summary = Format.scene_summary(cell.scene),
        }
      end
    end
    if #figures > 0 then
      out[#out + 1] = '<p class="toc-section">Figures</p>'
      for number, figure in ipairs(figures) do
        local summary = figure.summary
        local label = summary and type(summary.title) == "string" and
          summary.title ~= "" and summary.title or
          ("Cell " .. tostring(figure.index))
        out[#out + 1] = string.format(
          '<a class="toc-entry toc-figure" href="#figure-%d" data-cell="%d">Figure %d: %s</a>',
          number, figure.index, number, escape_html(label))
      end
    end
    out[#out + 1] = "</nav>"
  end

  out[#out + 1] = '<main id="content">'
  local figure_number = 0
  for index, cell in ipairs(notebook.cells) do
    local has_scene = cell.scene ~= nil and ' data-has-scene="true"' or ""
    out[#out + 1] = string.format(
      '<section class="cell" id="cell-%d" data-kind="%s" data-search="%s"%s>',
      index, escape_html(cell.kind or "code"),
      escape_html(Format.search_text(cell)), has_scene)
    out[#out + 1] = '<div class="cell-head"><span class="cell-label">' ..
      (cell.kind == "markdown" and "Markdown" or "Code") .. " cell " ..
      index .. '</span><a class="permalink" href="#cell-' .. index ..
      '" aria-label="Permalink to cell ' .. index .. '">#</a></div>'
    if cell.kind == "markdown" then
      out[#out + 1] = markdown_html(cell.source, by_cell[index],
        "cell-" .. index)
    else
      out[#out + 1] = code_block_html(cell.source or "", "lua")
      if cell.scene ~= nil then
        figure_number = figure_number + 1
        local figure = render_scene(cell.scene, figure_number)
        if figure ~= nil then out[#out + 1] = figure end
      end
      local widgets = render_widgets(cell)
      if widgets ~= nil then out[#out + 1] = widgets end
      if cell.error ~= nil and cell.error ~= "" then
        out[#out + 1] = '<pre class="error">' ..
          escape_html(cell.error) .. "</pre>"
      elseif cell.output ~= nil and cell.output ~= "" then
        out[#out + 1] = '<pre class="output">' ..
          escape_html(cell.output) .. "</pre>"
      end
    end
    out[#out + 1] = "</section>"
  end
  out[#out + 1] = "</main>"
  out[#out + 1] = "</div>"

  if backlinks ~= nil and #backlinks > 0 then
    out[#out + 1] = '<aside class="backlinks" aria-label="Backlinks">' ..
      "<strong>Backlinks:</strong> "
    for index, backlink in ipairs(backlinks) do
      if index > 1 then out[#out + 1] = ", " end
      out[#out + 1] = '<span class="backlink">' ..
        escape_html(backlink) .. "</span>"
    end
    out[#out + 1] = "</aside>"
  end
  out[#out + 1] = '<footer class="footer">Static export from ' ..
    "lua-notebooks · " .. stats.cells .. " cells · " .. #headings ..
    " heading(s) · " .. stats.tags .. " tag(s)</footer>"
  out[#out + 1] = "<script>" .. HTML_CODE_SCRIPT .. "</script>"
  out[#out + 1] = "<script>" .. HTML_SEARCH_SCRIPT .. "</script>"
  out[#out + 1] = "</body></html>"
  return table.concat(out, "\n")
end

function Format.list()
  local items = lovr.filesystem.getDirectoryItems("notebooks")
  local names = {}
  for _, item in ipairs(items) do
    if item:match("%.luanb$") then names[#names + 1] = item end
  end
  table.sort(names)
  return names
end

function Format.list_tree(expanded, prefix, depth, recurse)
  prefix = prefix or "notebooks"
  depth = depth or 0
  expanded = expanded or {}
  local entries = {}
  local ok, items = pcall(lovr.filesystem.getDirectoryItems, prefix)
  if not ok then return entries end
  table.sort(items)
  for _, item in ipairs(items) do
    local path = prefix .. "/" .. item
    if lovr.filesystem.isDirectory(path) then
      entries[#entries + 1] = { path = path, name = item, depth = depth,
        kind = "directory" }
      if expanded[path] or recurse then
        for _, child in ipairs(Format.list_tree(expanded, path, depth + 1,
            recurse)) do
          entries[#entries + 1] = child
        end
      end
    elseif item:match("%.luanb$") then
      entries[#entries + 1] = { path = path, name = item, depth = depth,
        kind = "file" }
    end
  end
  return entries
end

-- Keep only matching notebook files plus the directory rows that contain a
-- match.  Entries stay in their original depth-first order, so the filetree
-- can render a filtered tree without changing directory nesting.
function Format.filter_entries(entries, query)
  if type(query) ~= "string" or query:match("^%s*$") then return entries end
  local needle = query:lower()
  local matched = {}
  for _, item in ipairs(entries or {}) do
    if item.kind == "file" and
       item.name:lower():find(needle, 1, true) ~= nil then
      matched[item.path] = true
    end
  end
  local result = {}
  for _, item in ipairs(entries or {}) do
    if item.kind == "file" then
      if matched[item.path] then result[#result + 1] = item end
    else
      local prefix = item.path .. "/"
      for path in pairs(matched) do
        if path:sub(1, #prefix) == prefix then
          result[#result + 1] = item
          break
        end
      end
    end
  end
  return result
end

-- Case-insensitive substring filter over outline heading text.  An empty query
-- returns the original list unchanged.
function Format.filter_headings(headings, query)
  if type(query) ~= "string" or query == "" then return headings end
  local needle = query:lower()
  local result = {}
  for _, heading in ipairs(headings or {}) do
    if tostring(heading.text or ""):lower():find(needle, 1, true) ~= nil then
      result[#result + 1] = heading
    end
  end
  return result
end

-- Case-insensitive substring filter over tag names.
function Format.filter_tag_entries(entries, query)
  if type(query) ~= "string" or query == "" then return entries end
  local needle = query:lower()
  local result = {}
  for _, entry in ipairs(entries or {}) do
    if tostring(entry.tag or ""):lower():find(needle, 1, true) ~= nil then
      result[#result + 1] = entry
    end
  end
  return result
end

function Format.create_folder(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
  if name == "" or name:find("%.%.") or name:find("/") then
    return nil, "invalid folder name"
  end
  local path = "notebooks/" .. name
  local ok, err = lovr.filesystem.createDirectory(path)
  if not ok then return nil, err end
  return path
end

function Format.rename(old_name, new_name)
  if not new_name:match("%.luanb$") then new_name = new_name .. ".luanb" end
  if new_name:find("%.%.") or new_name:sub(1, 1) == "/" then
    return nil, "invalid notebook name"
  end
  local root = lovr.filesystem.getSaveDirectory() .. "/notebooks/"
  local ok, err = os.rename(root .. old_name, root .. new_name)
  if not ok then return nil, err end
  return new_name
end

function Format.delete_path(path)
  local absolute = lovr.filesystem.getSaveDirectory() .. "/" .. path
  local ok, err = os.remove(absolute)
  if not ok then return nil, err end
  return true
end

function Format.delete(name)
  return Format.delete_path("notebooks/" .. name)
end

function Format.load_path(path)
  local text = lovr and lovr.filesystem and lovr.filesystem.read(path)
  if text == nil then
    local handle, err = io.open(path, "rb")
    if handle == nil then return nil, "not found: " .. path .. ": " .. tostring(err) end
    text = handle:read("*a")
    handle:close()
  end
  local ok, notebook = pcall(Format.decode, text)
  if not ok then return nil, tostring(notebook) end
  notebook._path = path
  return notebook
end

function Format.rename_path(old_path, new_name)
  if not new_name:match("%.luanb$") then new_name = new_name .. ".luanb" end
  if new_name:find("%.%.") or new_name:sub(1, 1) == "/" then
    return nil, "invalid notebook name"
  end
  local root = lovr.filesystem.getSaveDirectory() .. "/"
  local target = old_path:match("^(.*)/") or "notebooks"
  local new_path = target .. "/" .. new_name
  local ok, err = os.rename(root .. old_path, root .. new_path)
  if not ok then return nil, err end
  return new_path
end

function Format.load(name)
  local path = "notebooks/" .. name
  local text = lovr.filesystem.read(path)
  if text == nil then return nil, "not found: " .. path end
  return Format.decode(text)
end

return Format
