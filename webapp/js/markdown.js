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
  value = value.replace(/~~([^~]+)~~/g, "<del>$1</del>");
  value = value.replace(/\u0000(\d+)\u0000/g, (_, index) => slots[Number(index)]);
  return value;
}

export function renderMarkdown(source) {
  const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  let paragraph = [];
  let list = null;
  let code = null;
  let quote = [];

  const flushParagraph = () => {
    if (paragraph.length) {
      out.push(`<p>${inline(paragraph.join(" "))}</p>`);
      paragraph = [];
    }
  };
  const flushList = () => {
    if (list) {
      out.push(`<${list.type}>${list.items.map((item) => `<li>${inline(item)}</li>`).join("")}</${list.type}>`);
      list = null;
    }
  };
  const flushQuote = () => {
    if (quote.length) {
      out.push(`<blockquote>${quote.map((line) => `<p>${inline(line)}</p>`).join("")}</blockquote>`);
      quote = [];
    }
  };
  const flushAll = () => {
    flushParagraph();
    flushList();
    flushQuote();
  };

  for (const raw of lines) {
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
      flushList();
      quote.push(quoteMatch[1]);
      continue;
    }
    if (quote.length) flushQuote();

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
    const bullet = raw.match(/^\s*[-*+]\s+(.*)$/);
    if (bullet) {
      flushParagraph();
      flushQuote();
      if (!list || list.type !== "ul") { flushList(); list = { type: "ul", items: [] }; }
      list.items.push(bullet[1]);
      continue;
    }
    const ordered = raw.match(/^\s*\d+[.)]\s+(.*)$/);
    if (ordered) {
      flushParagraph();
      flushQuote();
      if (!list || list.type !== "ol") { flushList(); list = { type: "ol", items: [] }; }
      list.items.push(ordered[1]);
      continue;
    }
    if (list) flushList();
    paragraph.push(raw.trim());
  }
  if (code) out.push(`<pre><code>${escapeHtml(code.lines.join("\n"))}</code></pre>`);
  flushAll();
  return out.join("\n");
}
