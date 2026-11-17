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
