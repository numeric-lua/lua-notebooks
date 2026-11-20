# Neovim bridge review follow-up

Fixed after the static review:

- flat and batched `ext_linegrid` events are both accepted;
- one text path: printable characters come from `textinput`, special keys and
  Ctrl chords from `keypressed`;
- EOF/errors are detected, requests stop instead of spinning for five seconds;
- F10 fails closed and keeps the overlay open when the buffer cannot be read;
- Neovim edits go through the notebook undo stack;
- notebook markers are validated for duplicates, missing cells, bad indexes and
  text before the first marker;
- notebook-wide editing opens in normal mode on a body line, not on a marker;
- mouse events are routed to Neovim instead of stale notebook hitboxes;
- warm reloads go through a fresh scratch buffer and clear prior undo;
- F5 picks the cell from `nvim_win_get_cursor`, not the screen row;
- float32 decoding, partial sends, dead peers and server identity are handled;
- Linux/macOS use a private 0700 directory and Unix socket; temp files are 0600;
  no world-readable Neovim log remains.

Remaining limits:

- Windows uses the TCP transport; Unix sockets are POSIX-only.
- External popup-menu rendering is still disabled; completion falls back to the
  grid.
- Marker add/delete/reorder is rejected rather than mapped to the model.
- LÖVR key repeat is off by default, so holding Backspace/arrows does not repeat.
