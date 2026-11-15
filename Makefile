SHELL := /bin/sh
LUA ?= luajit

.PHONY: test run clean

test:
	$(LUA) tests/run.lua

run:
	lovr .

clean:
	rm -rf .lovrshadercache
