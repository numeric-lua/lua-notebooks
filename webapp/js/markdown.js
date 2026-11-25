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
      const interactive = context && context.interactiveTasks;
      if (interactive) context.taskIndex = (context.taskIndex || 0) + 1;
      const index = interactive ? ` data-task-index="${context.taskIndex}"` : "";
      const disabled = interactive ? "" : " disabled";
      body = `<li class="task-list-item${item.checked ? " done" : ""}">` +
        `<input type="checkbox"${disabled}${index}${item.checked ? " checked" : ""}> ` +
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

const CALLOUT_TITLES = {
  note: "Note",
  tip: "Tip",
  important: "Important",
  warning: "Warning",
  caution: "Caution",
};

function calloutMarker(entry) {
  if (!entry || entry.depth !== 1) return null;
  const match = String(entry.text).match(/^\s*\[!([a-z]+)\]\s*(.*)$/i);
  if (!match) return null;
  const kind = match[1].toLowerCase();
  if (!CALLOUT_TITLES[kind]) return null;
  return { kind, rest: match[2] };
}

function quoteHtml(entries, context) {
  const renderFrom = (list, start, depth) => {
    const out = [];
    let index = start;
    while (index < list.length && list[index].depth >= depth) {
      if (list[index].depth === depth) {
        if (list[index].text !== "") {
          out.push(`<p>${inline(list[index].text, context)}</p>`);
        }
        index += 1;
      } else {
        const childStart = index;
        while (index < list.length && list[index].depth > depth) {
          index += 1;
        }
        out.push(`<blockquote>${renderFrom(list, childStart, depth + 1)}</blockquote>`);
      }
    }
    return out.join("");
  };

  const marker = calloutMarker(entries[0]);
  if (marker) {
    const body = [];
    if (marker.rest) body.push({ depth: 1, text: marker.rest });
    body.push(...entries.slice(1));
    return `<div class="callout callout-${marker.kind}">` +
      `<p class="callout-title">${CALLOUT_TITLES[marker.kind]}</p>` +
      `${renderFrom(body, 0, 1)}</div>`;
  }
  return `<blockquote>${renderFrom(entries, 0, 1)}</blockquote>`;
}

function slugify(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/<[^>]*>/g, "")
    .replace(/[`*_~=\[\]]/g, "")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-") || "section";
}

function uniqueSlug(text, context) {
  const base = slugify(text);
  const count = (context.slugCounts.get(base) || 0) + 1;
  context.slugCounts.set(base, count);
  return count === 1 ? base : `${base}-${count}`;
}

function definitionListHtml(lines, index, context) {
  const items = [];
  let cursor = index;
  while (cursor < lines.length) {
    const term = lines[cursor];
    const definition = (lines[cursor + 1] || "").match(/^\s*:\s+(.*)$/);
    if (!definition || !term.trim() || /^\s*[#>\-:]/.test(term)) break;
    items.push(`<dt>${inline(term.trim(), context)}</dt>` +
      `<dd>${inline(definition[1], context)}</dd>`);
    cursor += 2;
  }
  return { html: `<dl>${items.join("")}</dl>`, next: cursor };
}

function codeBlockHtml(code) {
  const language = String(code.lang || "").replace(/[^\w+_-]/g, "") || "text";
  return `<div class="code-block"><div class="code-head">` +
    `<span class="code-lang">${escapeHtml(language)}</span>` +
    `<button type="button" class="copy-code">Copy</button></div>` +
    `<pre><code class="language-${language}">` +
    `${escapeHtml(code.lines.join("\n"))}</code></pre></div>`;
}

export function renderMarkdown(source, prefix = "md", options = {}) {
  const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
  const context = footnoteContext(source);
  context.prefix = String(prefix).replace(/[^\w-]/g, "-") || "md";
  context.interactiveTasks = options.interactiveTasks === true;
  context.taskIndex = 0;
  context.slugCounts = new Map();
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
        out.push(codeBlockHtml(code));
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
    const displayMath = raw.match(/^\s*\$\$(.*)\$\$\s*$/);
    if (displayMath && displayMath[1].trim()) {
      flushAll();
      out.push(`<div class="math-display">${escapeHtml(displayMath[1].trim())}</div>`);
      continue;
    }
    if (/^\s*\$\$\s*$/.test(raw)) {
      flushAll();
      const math = [];
      index += 1;
      while (index < lines.length && !/^\s*\$\$\s*$/.test(lines[index])) {
        math.push(lines[index]);
        index += 1;
      }
      out.push(`<div class="math-display">${escapeHtml(math.join("\n"))}</div>`);
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

    const nextDefinition = /^\s*:\s+/.test(lines[index + 1] || "");
    if (nextDefinition && raw.trim() && !/^\s*[#>\-:]/.test(raw)) {
      flushAll();
      const list = definitionListHtml(lines, index, context);
      out.push(list.html);
      index = list.next - 1;
      continue;
    }

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
      const slug = uniqueSlug(heading[2], context);
      const id = `${context.prefix}-${slug}`;
      out.push(`<h${level} id="${id}">${inline(heading[2], context)}` +
        `<a class="heading-permalink" href="#${id}" ` +
        `aria-label="Permalink to ${escapeHtml(heading[2])}">#</a></h${level}>`);
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
  if (code) out.push(codeBlockHtml(code));
  flushAll();
  const footnotes = footnoteSection(context);
  if (footnotes) out.push(footnotes);
  return out.join("\n");
}

// Toggle the nth Markdown task item (1-based) in source.  Fenced code is
// skipped, so a looked-like checkbox inside code never changes.  Returns the
// updated source, or null when the index is out of range.
export function toggleTaskAt(source, taskIndex) {
  const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
  let index = 0;
  let inCode = false;
  for (let line = 0; line < lines.length; line += 1) {
    if (/^\s*[`~]{3,}/.test(lines[line])) {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;
    const match = lines[line].match(/^(\s*[-*+]\s+\[)([ xX])(\].*)$/);
    if (!match) continue;
    index += 1;
    if (index === taskIndex) {
      lines[line] = match[1] + (match[2].toLowerCase() === "x" ? " " : "x") +
        match[3];
      return lines.join("\n");
    }
  }
  return null;
}
