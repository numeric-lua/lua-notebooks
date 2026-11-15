SHELL := /bin/sh
LUA ?= luajit

.PHONY: test run clean

test:
	$(LUA) tests/run.lua
	$(LUA) tests/widgets.lua
	$(LUA) tests/process.lua

run:
	lovr .

clean:
	rm -rf .lovrshadercache
