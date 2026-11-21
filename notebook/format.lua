--
-- .luanb persistence.  Pure encode/decode is testable without LÖVR; save/load
-- use the LÖVR filesystem, which confines writes to the app save directory.
--
local json = require("notebook.json")
local Notebook = require("notebook.model")

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

local function inline_markdown(text)
  local escaped = escape_html(text)
  escaped = escaped:gsub("%[%[([^%]]+)%]%]", function(target)
    return '<span class="wiki-link" data-target="' .. target .. '">' ..
      target .. "</span>"
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
    return '<a href="' .. url .. '"' .. rel .. ">" .. label .. "</a>"
  end)
  escaped = escaped:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
  escaped = escaped:gsub("`([^`]*)`", "<code>%1</code>")
  return escaped
end

-- Small, readable Markdown renderer for static exports.  It intentionally
-- covers the subset the editor previews: headings, lists, quotes, fenced code,
-- emphasis, inline code, links, and wiki links.
local function markdown_html(source, headings)
  local out = {}
  local fence, fence_language, fence_lines = nil, nil, {}
  local paragraph, list_kind, list_items = {}, nil, {}
  local heading_index = 0

  local function flush_paragraph()
    if #paragraph > 0 then
      out[#out + 1] = "<p>" .. table.concat(paragraph, "\n") .. "</p>"
      paragraph = {}
    end
  end

  local function flush_list()
    if list_kind ~= nil then
      out[#out + 1] = "<" .. list_kind .. ">" ..
        table.concat(list_items) .. "</" .. list_kind .. ">"
      list_kind, list_items = nil, {}
    end
  end

  local function flush_fence()
    if fence ~= nil then
      local class = ""
      if fence_language ~= nil and fence_language ~= "" then
        class = ' class="language-' .. escape_html(fence_language) .. '"'
      end
      out[#out + 1] = '<pre class="source"><code' .. class .. ">" ..
        table.concat(fence_lines, "\n") .. "</code></pre>"
      fence, fence_language, fence_lines = nil, nil, {}
    end
  end

  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    local marker, language = line:match(
      "^%s*([`~][`~][`~]+)%s*([%w_+%-]*)%s*$")
    if fence ~= nil then
      if marker ~= nil and marker:sub(1, 1) == fence:sub(1, 1) and
         #marker >= #fence then
        flush_fence()
      else
        fence_lines[#fence_lines + 1] = escape_html(line)
      end
    elseif marker ~= nil then
      flush_paragraph(); flush_list()
      fence, fence_language = marker, language or ""
    else
      local hashes, raw = line:match("^%s*(#+)%s+(.+)$")
      if hashes ~= nil and #hashes <= 6 then
        flush_paragraph(); flush_list()
        heading_index = heading_index + 1
        local heading = headings and headings[heading_index] or nil
        local id = heading and (' id="' .. escape_html(heading.id) .. '"') or ""
        out[#out + 1] = "<h" .. #hashes .. id .. ">" ..
          inline_markdown(raw:gsub("%s+#+%s*$", "")) .. "</h" .. #hashes .. ">"
      elseif line:match("^%s*[-*+]%s+") then
        flush_paragraph()
        if list_kind ~= "ul" then flush_list(); list_kind = "ul" end
        list_items[#list_items + 1] = "<li>" ..
          inline_markdown(line:gsub("^%s*[-*+]%s+", "")) .. "</li>"
      elseif line:match("^%s*%d+%.%s+") then
        flush_paragraph()
        if list_kind ~= "ol" then flush_list(); list_kind = "ol" end
        list_items[#list_items + 1] = "<li>" ..
          inline_markdown(line:gsub("^%s*%d+%.%s+", "")) .. "</li>"
      elseif line:match("^%s*>%s?") then
        flush_paragraph(); flush_list()
        out[#out + 1] = "<blockquote>" ..
          inline_markdown(line:gsub("^%s*>%s?", "")) .. "</blockquote>"
      elseif line:match("^%s*$") then
        flush_paragraph(); flush_list()
      else
        flush_list()
        paragraph[#paragraph + 1] = inline_markdown(line:gsub("^%s+", ""))
      end
    end
  end
  flush_fence(); flush_paragraph(); flush_list()
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
    string.format("luaplotlib scene with %d series and %d points",
      summary.count, summary.points)
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

function Format.html_stats(notebook)
  local stats = {
    cells = #notebook.cells,
    code = 0,
    markdown = 0,
    figures = 0,
    widgets = 0,
    words = 0,
    tags = 0,
  }
  for _, cell in ipairs(notebook.cells) do
    if cell.kind == "markdown" then
      stats.markdown = stats.markdown + 1
      for _ in (cell.source or ""):gmatch("%S+") do
        stats.words = stats.words + 1
      end
    else
      stats.code = stats.code + 1
    end
    if cell.scene ~= nil then stats.figures = stats.figures + 1 end
    stats.widgets = stats.widgets + #Format.widget_summary(cell)
  end
  for _ in pairs(Format.tags(notebook.cells)) do
    stats.tags = stats.tags + 1
  end
  return stats
end

local function render_scene(scene, number)
  local summary = Format.scene_summary(scene)
  if summary == nil then return nil end
  local out = { string.format(
    '<figure class="scene" id="figure-%d" data-scene="%s">', number,
    escape_html(summary.type or "scene")) }
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
pre.output{background:var(--output);border-left:4px solid #4d9b6a}
pre.error{background:var(--error);border-left:4px solid #c94b4b;color:#b42323}
@media (prefers-color-scheme:dark){pre.error{color:#ff9c9c}}
.cell blockquote{margin:.7rem 0;padding:.35rem 0 .35rem 1rem;border-left:3px solid var(--border);color:var(--muted)}
.cell h1,.cell h2,.cell h3,.cell h4,.cell h5,.cell h6{line-height:1.25;margin:1.1rem 0 .5rem}
.cell h1{font-size:1.55rem}
.cell h2{font-size:1.3rem}
.cell h3{font-size:1.12rem}
.cell ul,.cell ol{margin:.5rem 0 .8rem;padding-left:1.4rem}
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
@media (max-width:760px){.layout{display:block;padding-top:0}.toc{position:static;max-height:none;margin-bottom:1.4rem}h1{font-size:1.7rem}}
@media print{:root{--bg:#fff;--fg:#000;--muted:#444;--card:#fff;--code:#f4f4f4;--output:#f4f4f4;--border:#ccc;--figure:#fff}.toc,.skip,.permalink{display:none!important}.layout{display:block;max-width:none;padding:0}.document-header{padding:0 0 1rem}.cell{box-shadow:none;break-inside:avoid;page-break-inside:avoid}a{color:#000;text-decoration:none}.scene details{display:none}}
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
    '<html lang="en">',
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
          '<a class="toc-entry toc-level-%d" href="#%s">%s</a>',
          heading.level, escape_html(heading.id),
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
          '<a class="toc-entry toc-figure" href="#figure-%d">Figure %d: %s</a>',
          number, number, escape_html(label))
      end
    end
    out[#out + 1] = "</nav>"
  end

  out[#out + 1] = '<main id="content">'
  local figure_number = 0
  for index, cell in ipairs(notebook.cells) do
    out[#out + 1] = string.format(
      '<section class="cell" id="cell-%d" data-kind="%s">', index,
      escape_html(cell.kind or "code"))
    out[#out + 1] = '<div class="cell-head"><span class="cell-label">' ..
      (cell.kind == "markdown" and "Markdown" or "Code") .. " cell " ..
      index .. '</span><a class="permalink" href="#cell-' .. index ..
      '" aria-label="Permalink to cell ' .. index .. '">#</a></div>'
    if cell.kind == "markdown" then
      out[#out + 1] = markdown_html(cell.source, by_cell[index])
    else
      out[#out + 1] = '<pre class="source"><code class="language-lua">' ..
        escape_html(cell.source or "") .. "</code></pre>"
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

function Format.list_tree(expanded, prefix, depth)
  prefix = prefix or "notebooks"
  depth = depth or 0
  local entries = {}
  local ok, items = pcall(lovr.filesystem.getDirectoryItems, prefix)
  if not ok then return entries end
  table.sort(items)
  for _, item in ipairs(items) do
    local path = prefix .. "/" .. item
    if lovr.filesystem.isDirectory(path) then
      entries[#entries + 1] = { path = path, name = item, depth = depth,
        kind = "directory" }
      if expanded[path] then
        for _, child in ipairs(Format.list_tree(expanded, path, depth + 1)) do
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
