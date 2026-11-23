import test from "node:test";
import assert from "node:assert/strict";
import { renderMarkdown } from "../js/markdown.js";

test("renders headings and paragraphs", () => {
  const html = renderMarkdown("# Title\n\nA paragraph.");
  assert.match(html, /<h1>Title<\/h1>/);
  assert.match(html, /<p>A paragraph\.<\/p>/);
});

test("escapes raw HTML", () => {
  const html = renderMarkdown('<script>alert("x")</script>');
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /&lt;script&gt;/);
});

test("renders fenced code and inline code", () => {
  const html = renderMarkdown("```lua\nreturn 6 * 7\n```\n\nUse `print`.");
  assert.match(html, /<pre><code>return 6 \* 7<\/code><\/pre>/);
  assert.match(html, /<code>print<\/code>/);
});

test("rejects javascript links", () => {
  const html = renderMarkdown("[click](javascript:alert(1))");
  assert.doesNotMatch(html, /javascript:/);
  assert.match(html, /href="#"/);
});

test("renders lists and blockquotes", () => {
  const html = renderMarkdown("- one\n- two\n\n> quoted");
  assert.match(html, /<ul><li>one<\/li><li>two<\/li><\/ul>/);
  assert.match(html, /<blockquote><p>quoted<\/p><\/blockquote>/);
});

test("renders horizontal rules and strikethrough", () => {
  const html = renderMarkdown("Before\n\n---\n\nRetired ~~old~~ text.");
  assert.match(html, /<p>Before<\/p>/);
  assert.match(html, /<hr>/);
  assert.match(html, /<p>Retired <del>old<\/del> text\.<\/p>/);
  assert.doesNotMatch(html, /<p>----------<\/p>/);
});

test("preserves an ordered list start number", () => {
  const html = renderMarkdown("3) third\n4) fourth\n\n1. one");
  assert.match(html, /<ol start="3"><li>third<\/li><li>fourth<\/li><\/ol>/);
  assert.match(html, /<ol><li>one<\/li><\/ol>/);
});

test("renders Markdown task lists as disabled checkboxes", () => {
  const html = renderMarkdown("- [x] done **now**\n- [ ] later");
  assert.match(html, /<ul class="task-list">/);
  assert.match(html, /<li class="task-list-item done"><input type="checkbox" disabled checked> done <strong>now<\/strong><\/li>/);
  assert.match(html, /<li class="task-list-item"><input type="checkbox" disabled> later<\/li>/);
  assert.doesNotMatch(html, /<input type="checkbox" disabled checked> later/);
});
