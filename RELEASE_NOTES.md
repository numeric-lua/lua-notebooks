# lua-notebooks 1.34.2

- Esc leaves the inline cell without synchronous RPC or window freeze;
- source is synchronized live and flushed in the background with a short timeout;
- leaving resets notebook scope and keeps the cursor on the same line;
- one Esc exits from normal mode.
