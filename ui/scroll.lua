--
-- Pure scroll math.  Kept out of the LÖVR draw code so the oscillation bug
-- can be regression-tested without a window.
--
local Scroll = {}

local TOP = 60
local FOOTER = 38
local CONTENT_TOP = 66

function Scroll.max_scroll(content_height, viewport_height, content_top)
  content_top = content_top or CONTENT_TOP
  return math.max(0, content_top + content_height - viewport_height + 40)
end

function Scroll.target_scroll(scroll, cell_y, cell_height, viewport_height,
                              content_height, content_top, hide_footer)
  content_top = content_top or CONTENT_TOP
  local bottom = viewport_height - (hide_footer and 12 or FOOTER)
  local target = scroll
  if cell_height > bottom - TOP or cell_y < TOP then
    target = scroll + cell_y - content_top
  elseif cell_y + cell_height > bottom then
    target = scroll + cell_y + cell_height - bottom
  end
  return math.max(0, math.min(
    Scroll.max_scroll(content_height, viewport_height, content_top), target))
end

return Scroll
