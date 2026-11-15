# Process kernels (experimental)

The default kernel backend is still one persistent **LÖVR thread** per notebook.
Process mode moves each kernel into a plain-LuaJIT child process.

```sh
LUANB_KERNEL_MODE=process lovr .
```

## Protocol

Each notebook gets a work directory under:

```text
/tmp/lua-notebooks-process-<time>-<notebook>/
```

The host atomically writes `job.json`; the child atomically writes
`result.json`. Only one request is in flight per notebook.

```json
{"id": 4, "cell": "1:2", "code": "print('hello')"}
{"id": 4, "ok": true, "output": "hello", "widgets": []}
```

Widget events use the same channel:

```json
{"id": 5, "cell": "1:6", "widget": "w1", "event": {"type": "change", "value": 7}}
```

The child is `kernel/process_worker.lua`; it uses the same widget model and
capture logic as the thread worker. It has no graphics access.

## Lifecycle

- `os.execute` starts `luajit kernel/process_worker.lua <dir> <root>`.
- The child writes `pid` and `ready`.
- The host polls result files during `lovr.update`.
- On quit, the supervisor kills the child and removes its directory.
- A timeout (8 s) marks the cell as failed and restarts the notebook's child.
- A child that exits unexpectedly cannot take down the notebook.

## Limitations

- Linux/macOS only in this spike.
- File polling adds a small latency per job; cell execution dominates.
- One in-flight job per kernel; rapid widget events are serialized by the host.
- No automatic restart for a child that dies between requests (only timeout
  recovery).
- Process mode does not yet use OS resource limits or a sandbox.
- The thread backend remains the default and the fallback.

## Verification

```sh
make test
LUANB_KERNEL_MODE=process LUANB_SMOKE=1 lovr .
LUANB_KERNEL_MODE=process LUANB_SMOKE_WIDGET_EVENT=1 lovr .
LUANB_KERNEL_MODE=process LUANB_SMOKE_PROCESS_CRASH=1 lovr .
```

The crash smoke runs `os.exit(1)` in a child; the host reports a timeout,
restarts the child, and exits cleanly.
