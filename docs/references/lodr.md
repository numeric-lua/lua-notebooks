# Hot reload reference

- `lodr` (by Andi McClure) is a small LÖVR hot-loader. On desktop it watches a
  project directory and relaunches LÖVR when files change.
- LÖVR itself exposes `lovr.filesystem.watch(path, callback)` and the
  `lovr.filechanged` callback for lighter-weight reloads.
- For notebooks, hot reload should apply to **extensions and notebook source**,
  not to the kernel state: reload UI/scene modules, preserve kernel variables,
  and explicitly reset a kernel when its source contract changes.

The important design rule: a reload must not execute untrusted notebook code in
the host process. Reload extension manifests and scene renderers; ask the
kernel supervisor to restart the kernel when its code changes.
