SHELL := /bin/sh
LUA ?= luajit

.PHONY: test run package install install-desktop clean

test:
	$(LUA) tests/run.lua
	$(LUA) tests/widgets.lua
	$(LUA) tests/process.lua
	$(LUA) tests/sandbox.lua

run:
	lovr .

package:
	./scripts/package.sh

install:
	./scripts/install.sh

install-desktop:
	INSTALL_DESKTOP=1 ./scripts/install.sh

clean:
	rm -rf .lovrshadercache dist
