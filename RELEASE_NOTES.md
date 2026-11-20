# lua-notebooks 1.23.0

- Neovim uses a private Unix socket on Linux/macOS, with TCP fallback on Windows;
- per-session private socket directory and mode-600 buffers;
- no world-readable Neovim log;
- OSX sockaddr layout and O_NONBLOCK handling;
- flat/batched linegrid events, single input path, dead-peer and save-failure handling.
