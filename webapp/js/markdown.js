const ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ESCAPES[ch]);
}

function safeUrl(url) {
  const trimmed = String(url).trim();
  if (/^(https?:|mailto:|#|\/|\.\/|\.\.\/)/i.test(trimmed)) return trimmed;
  return "#";
}

function trimAutolink(url) {
  let trimmed = String(url);
  for (;;) {
    const last = trimmed.slice(-1);
    if (last === "." || last === "," || last === ":" || last === "!" || last === "?") {
      trimmed = trimmed.slice(0, -1);
    } else if (last === ";") {
      if (/&[a-z#][\w#]*;$/i.test(trimmed)) break;
      trimmed = trimmed.slice(0, -1);
    } else if (last === ")") {
      const opens = (trimmed.match(/\(/g) || []).length;
      const closes = (trimmed.match(/\)/g) || []).length;
      if (closes > opens) trimmed = trimmed.slice(0, -1);
      else break;
    } else {
      break;
    }
  }
  return { link: trimmed, trailing: String(url).slice(trimmed.length) };
}

function footnoteContext(source) {
  const context = {
    definitions: new Map(),
    numbers: new Map(),
    order: [],
    prefix: "md",
  };
  let inCode = false;
  for (const raw of String(source || "").replace(/\r\n/g, "\n").split("\n")) {
    if (/^\s*[`~]{3,}/.test(raw)) {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;
    const definition = raw.match(/^\s*\[\^([\w-]+)\]:\s*(.*)$/);
    if (definition && !context.definitions.has(definition[1])) {
      context.definitions.set(definition[1], definition[2]);
    }
  }
  return context;
}

function footnoteNumber(label, context) {
  if (!context || !context.definitions.has(label)) return null;
  let number = context.numbers.get(label);
  if (number === undefined) {
    number = context.order.length + 1;
    context.numbers.set(label, number);
    context.order.push(label);
  }
  return number;
}

function footnoteRef(label, context) {
  const number = footnoteNumber(label, context);
  if (number === null) return null;
  const prefix = context.prefix;
  return `<sup class="footnote-ref" id="fnref-${prefix}-${number}">` +
    `<a href="#fn-${prefix}-${number}">${number}</a></sup>`;
}

function footnoteSection(context) {
  if (!context || context.order.length === 0) return "";
  const prefix = context.prefix;
  const items = [];
  // Definition bodies can reference other footnotes; walk the growing order
  // list so those references get their own endnote entry too.
  for (let index = 0; index < context.order.length; index += 1) {
    const label = context.order[index];
    const number = context.numbers.get(label);
    const body = inline(context.definitions.get(label) || "", context);
    items.push(`<li id="fn-${prefix}-${number}">${body} ` +
      `<a class="footnote-back" href="#fnref-${prefix}-${number}" ` +
      `aria-label="Back to footnote ${number}">↩</a></li>`);
  }
  return `<section class="footnotes" role="doc-endnotes"><hr><ol>` +
    `${items.join("")}</ol></section>`;
}

function inline(text, context = null) {
  let value = escapeHtml(text);
  const slots = [];
  const hold = (html) => `\u0000${slots.push(html) - 1}\u0000`;

  // Backslash escapes are literal, so keep them away from code and emphasis.
  value = value.replace(/\\([\\`*_{}\[\]()#+.!~=|%-])/g, (_, char) => hold(char));
  value = value.replace(/`([^`]+)`/g, (_, code) => hold(`<code>${code}</code>`));
  value = value.replace(/\$\$([^$]+)\$\$/g, (_, math) =>
    hold(`<span class="math">${math}</span>`));
  value = value.replace(/\$([^$]+)\$/g, (_, math) =>
    hold(`<span class="math">${math}</span>`));
  value = value.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) =>
    hold(`<a href="${escapeHtml(safeUrl(url))}" target="_blank" rel="noreferrer">${label}</a>`));
  // Explicit links are already held, so this never links their destination or
  // label twice.  The text is HTML-escaped at this point, so it is reused as-is.
  value = value.replace(/https?:\/\/[^\s]+/g, (url) => {
    const { link, trailing } = trimAutolink(url);
    if (!link) return url;
    return hold(`<a href="${link}" target="_blank" rel="noreferrer">${link}</a>`) + trailing;
  });
  value = value.replace(/==([^=]+)==/g, "<mark>$1</mark>");
  value = value.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  value = value.replace(/__([^_]+)__/g, "<strong>$1</strong>");
  value = value.replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
  value = value.replace(/(^|[^_\w])_([^_]+)_/g, "$1<em>$2</em>");
  value = value.replace(/~~([^~]+)~~/g, "<del>$1</del>");
  if (context) {
    value = value.replace(/\[\^([\w-]+)\]/g, (match, label) =>
      footnoteRef(label, context) ?? match);
  }
  let restored = value;
  for (;;) {
    const next = restored.replace(/\u0000(\d+)\u0000/g, (_, index) =>
      slots[Number(index)] ?? "");
    if (next === restored) return restored;
    restored = next;
  }
}

function tableCells(line) {
  if (!line.includes("|")) return null;
  const marker = "\u0001";
  let trimmed = String(line).trim().replace(/\\\|/g, marker);
  if (trimmed.startsWith("|")) trimmed = trimmed.slice(1);
  if (trimmed.endsWith("|")) trimmed = trimmed.slice(0, -1);
  return trimmed.split("|").map((cell) => cell.split(marker).join("|").trim());
}

function tableAlignments(line) {
  const cells = tableCells(line);
  if (!cells || cells.length === 0) return null;
  const alignments = [];
  for (const cell of cells) {
    const value = cell.replace(/\s+/g, "");
    if (!/^:?-+:?$/.test(value)) return null;
    if (value.startsWith(":") && value.endsWith(":")) alignments.push("center");
    else if (value.endsWith(":")) alignments.push("right");
    else alignments.push("left");
  }
  return alignments;
}

function tableHtml(lines, index, header, alignments, context) {
  const row = (cells, tag) => "<tr>" + alignments.map((alignment, column) => {
    const className = alignment !== "left" ? ` class="align-${alignment}"` : "";
    return `<${tag}${className}>${inline((cells[column] || "").trim(), context)}</${tag}>`;
  }).join("") + "</tr>";
  const html = ['<table class="markdown-table"><thead>', row(header, "th"),
    "</thead><tbody>"];
  let cursor = index + 2;
  while (cursor < lines.length) {
    const line = lines[cursor];
    if (!line.trim()) break;
    const cells = tableCells(line);
    if (!cells) break;
    html.push(row(cells, "td"));
    cursor += 1;
  }
  html.push("</tbody></table>");
  return { html: html.join(""), next: cursor };
}

function listIndent(prefix) {
  let width = 0;
  for (const character of prefix) width += character === "\t" ? 2 : 1;
  return width;
}

function listItem(line) {
  const match = line.match(/^(\s*)(.*)$/);
  if (!match) return null;
  const indent = listIndent(match[1]);
  const rest = match[2];
  const task = rest.match(/^[-*+]\s+\[([ xX])\]\s+(.*)$/);
  if (task) {
    return { indent, kind: "task", text: task[2], checked: task[1].toLowerCase() === "x" };
  }
  const bullet = rest.match(/^[-*+]\s+(.*)$/);
  if (bullet) return { indent, kind: "ul", text: bullet[1] };
  const ordered = rest.match(/^(\d+)[.)]\s+(.*)$/);
  if (ordered) return { indent, kind: "ol", text: ordered[2], start: Number(ordered[1]) || 1 };
  return null;
}

function renderList(entry, context) {
  const tag = entry.kind === "ol" ? "ol" : "ul";
  let attributes = "";
  if (entry.kind === "task") attributes = ' class="task-list"';
  else if (entry.kind === "ol" && entry.start !== 1) attributes = ` start="${entry.start}"`;
  const items = entry.items.map((item) => {
    let body;
    if (entry.kind === "task") {
      body = `<li class="task-list-item${item.checked ? " done" : ""}">` +
        `<input type="checkbox" disabled${item.checked ? " checked" : ""}> ` +
        inline(item.text, context);
    } else {
      body = `<li>${inline(item.text, context)}`;
    }
    body += (item.children || []).join("");
    return `${body}</li>`;
  }).join("");
  return `<${tag}${attributes}>${items}</${tag}>`;
}

function quoteDepth(line) {
  let depth = 0;
  let rest = String(line);
  for (;;) {
    const match = rest.match(/^(\s*>\s?)(.*)$/);
    if (!match) break;
    depth += 1;
    rest = match[2];
  }
  return { depth, text: rest };
}

function quoteHtml(entries, context) {
  const renderFrom = (start, depth) => {
    const out = [];
    let index = start;
    while (index < entries.length && entries[index].depth >= depth) {
      if (entries[index].depth === depth) {
        out.push(`<p>${inline(entries[index].text, context)}</p>`);
        index += 1;
      } else {
        const childStart = index;
        while (index < entries.length && entries[index].depth > depth) {
          index += 1;
        }
        out.push(`<blockquote>${renderFrom(childStart, depth + 1)}</blockquote>`);
      }
    }
    return out.join("");
  };
  return `<blockquote>${renderFrom(0, 1)}</blockquote>`;
}

export function renderMarkdown(source, prefix = "md") {
  const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
  const context = footnoteContext(source);
  context.prefix = String(prefix).replace(/[^\w-]/g, "-") || "md";
  const out = [];
  let paragraph = [];
  let listStack = [];
  let code = null;
  let quote = [];

  const flushParagraph = () => {
    if (paragraph.length) {
      out.push(`<p>${inline(paragraph.join(" "), context)}</p>`);
      paragraph = [];
    }
  };
  const closeList = () => {
    const entry = listStack.pop();
    if (!entry) return;
    const html = renderList(entry, context);
    const parent = listStack[listStack.length - 1];
    if (parent && parent.items.length) {
      parent.items[parent.items.length - 1].children.push(html);
    } else {
      out.push(html);
    }
  };
  const closeLists = () => {
    while (listStack.length) closeList();
  };
  const addListItem = (item) => {
    while (listStack.length && item.indent < listStack[listStack.length - 1].indent) {
      closeList();
    }
    let top = listStack[listStack.length - 1];
    if (top && top.indent === item.indent && top.kind !== item.kind) {
      closeList();
      top = listStack[listStack.length - 1];
    }
    if (!top || top.indent < item.indent) {
      top = { kind: item.kind, indent: item.indent, start: item.start || 1, items: [] };
      listStack.push(top);
    }
    top.items.push({ text: item.text, checked: item.checked === true, children: [] });
  };
  const flushQuote = () => {
    if (quote.length) {
      out.push(quoteHtml(quote, context));
      quote = [];
    }
  };
  const flushAll = () => {
    flushParagraph();
    closeLists();
    flushQuote();
  };

  for (let index = 0; index < lines.length; index += 1) {
    const raw = lines[index];
    if (code) {
      if (/^\s*```/.test(raw)) {
        out.push(`<pre><code>${escapeHtml(code.lines.join("\n"))}</code></pre>`);
        code = null;
      } else {
        code.lines.push(raw);
      }
      continue;
    }
    const fence = raw.match(/^\s*```(.*)$/);
    if (fence) {
      flushAll();
      code = { lang: fence[1].trim(), lines: [] };
      continue;
    }
    if (!raw.trim()) {
      flushAll();
      continue;
    }
    if (/^\s*\[\^[\w-]+\]:/.test(raw)) {
      // Definitions are rendered as the endnotes section below.
      flushAll();
      continue;
    }
    const quoted = quoteDepth(raw);
    if (quoted.depth > 0) {
      flushParagraph();
      closeLists();
      quote.push(quoted);
      continue;
    }
    if (quote.length) flushQuote();

    const header = tableCells(raw);
    const alignments = header ? tableAlignments(lines[index + 1] || "") : null;
    if (header && alignments) {
      flushAll();
      const table = tableHtml(lines, index, header, alignments, context);
      out.push(table.html);
      index = table.next - 1;
      continue;
    }

    const heading = raw.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      flushAll();
      const level = heading[1].length;
      out.push(`<h${level}>${inline(heading[2], context)}</h${level}>`);
      continue;
    }
    if (/^\s*([-*_])\s*\1\s*\1[\s\-*_]*$/.test(raw)) {
      flushAll();
      out.push("<hr>");
      continue;
    }
    const item = listItem(raw);
    if (item) {
      flushParagraph();
      flushQuote();
      addListItem(item);
      continue;
    }
    if (listStack.length) closeLists();
    paragraph.push(raw.trim());
  }
  if (code) out.push(`<pre><code>${escapeHtml(code.lines.join("\n"))}</code></pre>`);
  flushAll();
  const footnotes = footnoteSection(context);
  if (footnotes) out.push(footnotes);
  return out.join("\n");
}
