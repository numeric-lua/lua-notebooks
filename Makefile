SHELL := /bin/sh
LUA ?= luajit

.PHONY: test run package install install-desktop rock clean

test:
	$(LUA) tests/run.lua
	$(LUA) tests/widgets.lua
	$(LUA) tests/process.lua
	$(LUA) tests/sandbox.lua
	$(LUA) tests/platform.lua
	$(LUA) tests/display_list.lua
	$(LUA) tests/math_engine.lua
	$(LUA) tests/editor.lua
	$(LUA) tests/lsp_protocol.lua
	sh tests/lsp_stdio.sh
	sh tests/extension_sandbox.sh
	$(LUA) tests/lsp_client.lua
	$(LUA) tests/lsp_edits.lua
	$(LUA) tests/scope.lua

run:
	lovr .

package:
	./scripts/package.sh

install:
	./scripts/install.sh

install-desktop:
	INSTALL_DESKTOP=1 ./scripts/install.sh

rock:
	luarocks lint lua-notebooks-0.1.0-1.rockspec
	luarocks pack lua-notebooks-0.1.0-1.rockspec

clean:
	rm -rf .lovrshadercache dist *.src.rock
