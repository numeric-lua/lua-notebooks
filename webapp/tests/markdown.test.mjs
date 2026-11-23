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

test("renders pipe tables with alignment and inline formatting", () => {
  const html = renderMarkdown("| Item | Value |\n| :--- | ---: |\n| alpha | **1** |");
  assert.match(html, /<table class="markdown-table"><thead><tr><th>Item<\/th><th class="align-right">Value<\/th><\/tr><\/thead><tbody>/);
  assert.match(html, /<tr><td>alpha<\/td><td class="align-right"><strong>1<\/strong><\/td><\/tr>/);
  assert.match(html, /<\/tbody><\/table>/);
});

test("renders nested unordered, ordered, and task lists", () => {
  const html = renderMarkdown("- one\n  - two\n    3. three\n- four\n\n- [x] parent\n  - [ ] child");
  assert.match(html, /<ul><li>one<ul><li>two<ol start="3"><li>three<\/li><\/ol><\/li><\/ul><\/li><li>four<\/li><\/ul>/);
  assert.match(html, /<ul class="task-list"><li class="task-list-item done"><input type="checkbox" disabled checked> parent<ul class="task-list"><li class="task-list-item"><input type="checkbox" disabled> child<\/li><\/ul><\/li><\/ul>/);
});

test("aligns emphasis and grouped blockquotes with the export", () => {
  const html = renderMarkdown("*italic* _under_ __bold__ **strong** and `*literal*`\n\n> q1\n> q2");
  assert.match(html, /<p><em>italic<\/em> <em>under<\/em> <strong>bold<\/strong> <strong>strong<\/strong> and <code>\*literal\*<\/code><\/p>/);
  assert.match(html, /<blockquote><p>q1<\/p><p>q2<\/p><\/blockquote>/);
});

test("renders highlights, autolinks, and backslash escapes", () => {
  const html = renderMarkdown("==marked== and https://example.com/docs).\n\n\\*literal\\* and \\[brackets\\] and \\\\");
  assert.match(html, /<p><mark>marked<\/mark> and <a href="https:\/\/example.com\/docs" target="_blank" rel="noreferrer">https:\/\/example.com\/docs<\/a>\)\.<\/p>/);
  assert.match(html, /<p>\*literal\* and \[brackets\] and \\<\/p>/);
});

test("does not autolink inside code or an explicit link", () => {
  const html = renderMarkdown("`https://example.com` and [https://example.com](https://example.com)");
  assert.equal((html.match(/<a /g) || []).length, 1);
  assert.match(html, /<code>https:\/\/example.com<\/code>/);
  assert.match(html, /<a href="https:\/\/example.com" target="_blank" rel="noreferrer">https:\/\/example.com<\/a>/);
});

test("does not parse a table inside a fenced code block", () => {
  const html = renderMarkdown("```lua\n| a | b |\n| --- | --- |\n```");
  assert.doesNotMatch(html, /markdown-table/);
  assert.match(html, /<pre><code>\| a \| b \|/);
});
