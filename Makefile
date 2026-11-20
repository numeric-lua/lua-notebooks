SHELL := /bin/sh
LUA ?= luajit

.PHONY: test test-nvim bench test-remote test-webapp test-lua51 run package install install-desktop rock clean

bench:
	$(LUA) tests/bench_large.lua

test:
	$(LUA) tests/run.lua
	$(LUA) tests/runtime.lua
	$(LUA) tests/engine.lua
	$(LUA) tests/inline_supervisor.lua
	$(LUA) tests/remote_supervisor.lua
	$(LUA) tests/browser_transport.lua
	$(LUA) tests/widgets.lua
	$(LUA) tests/process.lua
	$(LUA) tests/sandbox.lua
	$(LUA) tests/platform.lua
	$(LUA) tests/display_list.lua
	$(LUA) tests/math_engine.lua
	$(LUA) tests/editor.lua
	$(LUA) tests/lsp_protocol.lua
	$(LUA) tests/gateway_policy.lua
	sh tests/lsp_stdio.sh
	sh tests/extension_sandbox.sh
	$(LUA) tests/lsp_client.lua
	$(LUA) tests/lsp_edits.lua
	$(LUA) tests/scope.lua

test-nvim:
	$(LUA) tests/nvim_grid.lua
	$(LUA) tests/nvim_rpc.lua
	$(LUA) tests/nvim_session.lua

test-remote:
	sh tests/remote_gateway.sh

test-webapp:
	sh webapp/test.sh

test-lua51:
	$(LUA) tests/run.lua
	$(LUA) tests/runtime.lua
	$(LUA) tests/engine.lua
	$(LUA) tests/inline_supervisor.lua
	$(LUA) tests/remote_supervisor.lua
	$(LUA) tests/browser_transport.lua
	$(LUA) tests/widgets.lua
	$(LUA) tests/sandbox.lua
	$(LUA) tests/platform.lua
	$(LUA) tests/display_list.lua
	$(LUA) tests/math_engine.lua
	$(LUA) tests/editor.lua
	$(LUA) tests/lsp_protocol.lua
	$(LUA) tests/gateway_policy.lua
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
	luarocks lint lua-notebooks-1.7.0-1.rockspec
	luarocks pack lua-notebooks-1.7.0-1.rockspec

clean:
	rm -rf .lovrshadercache dist *.src.rock
