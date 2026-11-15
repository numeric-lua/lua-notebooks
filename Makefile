SHELL := /bin/sh
LUA ?= luajit

.PHONY: test run package clean

test:
	$(LUA) tests/run.lua
	$(LUA) tests/widgets.lua
	$(LUA) tests/process.lua
	$(LUA) tests/sandbox.lua

run:
	lovr .

package:
	./scripts/package.sh

clean:
	rm -rf .lovrshadercache dist
