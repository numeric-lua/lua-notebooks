package = "lua-notebooks"
version = "1.54.0-1"

source = {
  url = "git://github.com/numeric-lua/lua-notebooks",
}

description = {
  summary = "Native LÖVR notebook workspace",
  detailed = [[
    A LÖVR-hosted notebook environment with Lua kernels, 3D extension
    surfaces, widgets, luaplotlib scenes (including live polar series,
    heatmaps, contours, quiver arrows, streamlines, and colourbars with bounded
    block sampling for large fields, deterministic arrow decimation, shared
    streamplot geometry, frame-clipped streamplot runs and arrow heads, and
    dashed/dotted/none streamplot line styles), an editor language service,
    hierarchical notebook navigation, literal or Lua-pattern find and replace
    with case/whole-word options, a cross-notebook search overlay, closable
    notebook tabs with an unsaved-changes guard, a navigable static HTML export
    with reader search, nested lists, pipe tables, task lists, italic and
    grouped blockquote rendering, thematic breaks, strikethrough, ordered-list
    starts, heading permalinks, copyable code blocks, and shared polar
    geometry, an expandable long-output view and notebook-statistics overlay,
    and a dependency-free browser front-end that renders Markdown and
    Cartesian/polar scenes on Canvas with the same geometry contract.
  ]],
  homepage = "https://github.com/numeric-lua/lua-notebooks",
  license = "BSD-3-Clause",
}

dependencies = {
  lua = "lua >= 5.1",
}

build = {
  type = "command",
  build_command = "true",
  install_command = [[
    mkdir -p "$(PREFIX)/share/lua-notebooks/scripts" "$(PREFIX)/bin"
    cp -R conf.lua main.lua README.md LICENSE notebook kernel ui extensions assets web webapp \
      "$(PREFIX)/share/lua-notebooks/"
    cp scripts/kernel-gateway.lua scripts/websocket.lua scripts/lsp-stdio.lua \
      "$(PREFIX)/share/lua-notebooks/scripts/"
    cp scripts/lua-notebooks "$(PREFIX)/bin/lua-notebooks"
    cp scripts/lua-notebooks-lsp "$(PREFIX)/bin/lua-notebooks-lsp"
    chmod +x "$(PREFIX)/bin/lua-notebooks" "$(PREFIX)/bin/lua-notebooks-lsp"
  ]],
}
