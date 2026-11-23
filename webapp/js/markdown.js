const ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ESCAPES[ch]);
}

function safeUrl(url) {
  const trimmed = String(url).trim();
  if (/^(https?:|mailto:|#|\/|\.\/|\.\.\/)/i.test(trimmed)) return trimmed;
  return "#";
}

function inline(text) {
  let value = escapeHtml(text);
  const slots = [];
  const hold = (html) => `\u0000${slots.push(html) - 1}\u0000`;

  value = value.replace(/`([^`]+)`/g, (_, code) => hold(`<code>${code}</code>`));
  value = value.replace(/\$\$([^$]+)\$\$/g, (_, math) =>
    hold(`<span class="math">${math}</span>`));
  value = value.replace(/\$([^$]+)\$/g, (_, math) =>
    hold(`<span class="math">${math}</span>`));
  value = value.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) =>
    hold(`<a href="${escapeHtml(safeUrl(url))}" target="_blank" rel="noreferrer">${label}</a>`));
  value = value.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  value = value.replace(/__([^_]+)__/g, "<strong>$1</strong>");
  value = value.replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
  value = value.replace(/(^|[^_\w])_([^_]+)_/g, "$1<em>$2</em>");
  value = value.replace(/~~([^~]+)~~/g, "<del>$1</del>");
  value = value.replace(/\u0000(\d+)\u0000/g, (_, index) => slots[Number(index)]);
  return value;
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

function tableHtml(lines, index, header, alignments) {
  const row = (cells, tag) => "<tr>" + alignments.map((alignment, column) => {
    const className = alignment !== "left" ? ` class="align-${alignment}"` : "";
    return `<${tag}${className}>${inline((cells[column] || "").trim())}</${tag}>`;
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

function renderList(entry) {
  const tag = entry.kind === "ol" ? "ol" : "ul";
  let attributes = "";
  if (entry.kind === "task") attributes = ' class="task-list"';
  else if (entry.kind === "ol" && entry.start !== 1) attributes = ` start="${entry.start}"`;
  const items = entry.items.map((item) => {
    let body;
    if (entry.kind === "task") {
      body = `<li class="task-list-item${item.checked ? " done" : ""}">` +
        `<input type="checkbox" disabled${item.checked ? " checked" : ""}> ` +
        inline(item.text);
    } else {
      body = `<li>${inline(item.text)}`;
    }
    body += (item.children || []).join("");
    return `${body}</li>`;
  }).join("");
  return `<${tag}${attributes}>${items}</${tag}>`;
}

export function renderMarkdown(source) {
  const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  let paragraph = [];
  let listStack = [];
  let code = null;
  let quote = [];

  const flushParagraph = () => {
    if (paragraph.length) {
      out.push(`<p>${inline(paragraph.join(" "))}</p>`);
      paragraph = [];
    }
  };
  const closeList = () => {
    const entry = listStack.pop();
    if (!entry) return;
    const html = renderList(entry);
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
      out.push(`<blockquote>${quote.map((line) => `<p>${inline(line)}</p>`).join("")}</blockquote>`);
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
    const quoteMatch = raw.match(/^>\s?(.*)$/);
    if (quoteMatch) {
      flushParagraph();
      closeLists();
      quote.push(quoteMatch[1]);
      continue;
    }
    if (quote.length) flushQuote();

    const header = tableCells(raw);
    const alignments = header ? tableAlignments(lines[index + 1] || "") : null;
    if (header && alignments) {
      flushAll();
      const table = tableHtml(lines, index, header, alignments);
      out.push(table.html);
      index = table.next - 1;
      continue;
    }

    const heading = raw.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      flushAll();
      const level = heading[1].length;
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
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
  return out.join("\n");
}
