import test from "node:test";
import assert from "node:assert/strict";
import { renderMarkdown, toggleTaskAt } from "../js/markdown.js";

test("renders headings and paragraphs", () => {
  const html = renderMarkdown("# Title\n\nA paragraph.");
  assert.match(html, /<h1 id="md-title">Title<a class="heading-permalink" href="#md-title"/);
  assert.match(html, /<p>A paragraph\.<\/p>/);
});

test("escapes raw HTML", () => {
  const html = renderMarkdown('<script>alert("x")</script>');
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /&lt;script&gt;/);
});

test("renders fenced code and inline code", () => {
  const html = renderMarkdown("```lua\nreturn 6 * 7\n```\n\nUse `print`.");
  assert.match(html, /<div class="code-block"><div class="code-head">/);
  assert.match(html, /<span class="code-lang">lua<\/span>/);
  assert.match(html, /<button type="button" class="copy-code">Copy<\/button>/);
  assert.match(html, /<pre><code class="language-lua">return 6 \* 7<\/code><\/pre>/);
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

test("renders nested blockquotes", () => {
  const html = renderMarkdown("> outer\n> > inner\n> outer again\n> > > deepest");
  assert.match(html,
    /<blockquote><p>outer<\/p><blockquote><p>inner<\/p><\/blockquote><p>outer again<\/p><blockquote><blockquote><p>deepest<\/p><\/blockquote><\/blockquote><\/blockquote>/);
});

test("renders GitHub-style callout blockquotes", () => {
  const html = renderMarkdown(
    "> [!WARNING]\n> Careful with **this**.\n>\n> Second paragraph.\n\n> [!UNKNOWN]\n> Not a callout.");
  assert.match(html,
    /<div class="callout callout-warning"><p class="callout-title">Warning<\/p><p>Careful with <strong>this<\/strong>.<\/p><p>Second paragraph.<\/p><\/div>/);
  assert.doesNotMatch(html, /callout-unknown/);
  assert.match(html, /<p>\[!UNKNOWN\]<\/p>/);
});

test("renders Markdown definition lists", () => {
  const html = renderMarkdown(
    "Alpha\n: first **term**\nBeta\n: second term\n\nNormal paragraph.");
  assert.match(html,
    /<dl><dt>Alpha<\/dt><dd>first <strong>term<\/strong><\/dd><dt>Beta<\/dt><dd>second term<\/dd><\/dl>/);
  assert.match(html, /<p>Normal paragraph\.<\/p>/);
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
  assert.match(html, /<pre><code class="language-lua">\| a \| b \|/);
});

test("renders footnote references and endnotes with a stable prefix", () => {
  const html = renderMarkdown(
    "Alpha[^a] and beta[^b].\n\n[^a]: first *note*\n[^b]: second note",
    "cell-7");
  assert.match(html, /Alpha<sup class="footnote-ref" id="fnref-cell-7-1"><a href="#fn-cell-7-1">1<\/a><\/sup>/);
  assert.match(html, /beta<sup class="footnote-ref" id="fnref-cell-7-2"><a href="#fn-cell-7-2">2<\/a><\/sup>/);
  assert.match(html, /<section class="footnotes" role="doc-endnotes"><hr><ol>/);
  assert.match(html, /<li id="fn-cell-7-1">first <em>note<\/em> /);
  assert.match(html, /<a class="footnote-back" href="#fnref-cell-7-1"/);
});

test("keeps undefined and escaped footnotes literal and ignores code", () => {
  const html = renderMarkdown(
    "`code[^a]` and \\[^a] and [^missing].\n\n```\n[^a]: hidden\n```\n\n[^a]: shown");
  assert.match(html, /<code>code\[\^a\]<\/code>/);
  assert.match(html, /\[\^a\] and \[\^missing\]/);
  assert.doesNotMatch(html, /fnref-md-1/);
});

test("numbers definitions in first-reference order", () => {
  const html = renderMarkdown("[^b] then [^a]\n\n[^a]: A\n[^b]: B");
  assert.match(html, /<a href="#fn-md-1">1<\/a><\/sup> then <sup class="footnote-ref" id="fnref-md-2"><a href="#fn-md-2">2<\/a>/);
  assert.match(html, /<li id="fn-md-1">B /);
  assert.match(html, /<li id="fn-md-2">A /);
});

test("renders interactive task checkboxes only when requested", () => {
  const source = "- [ ] one\n- [x] two";
  const plain = renderMarkdown(source);
  assert.match(plain, /<input type="checkbox" disabled> one/);
  const interactive = renderMarkdown(source, "cell-1", { interactiveTasks: true });
  assert.match(interactive, /<input type="checkbox" data-task-index="1"> one/);
  assert.match(interactive, /<input type="checkbox" data-task-index="2" checked> two/);
  assert.doesNotMatch(interactive, /disabled/);
});

test("toggles the nth task line and skips fenced code", () => {
  const source = "- [ ] one\n\n```\n- [ ] hidden\n```\n\n- [x] two";
  assert.equal(toggleTaskAt(source, 1), "- [x] one\n\n```\n- [ ] hidden\n```\n\n- [x] two");
  assert.equal(toggleTaskAt(source, 2), "- [ ] one\n\n```\n- [ ] hidden\n```\n\n- [ ] two");
  assert.equal(toggleTaskAt(source, 3), null);
});

test("gives headings unique anchor ids and permalinks", () => {
  const html = renderMarkdown("# Intro\n\n## Intro\n\n### Other *part*");
  assert.match(html, /<h1 id="md-intro">Intro<a class="heading-permalink" href="#md-intro"/);
  assert.match(html, /<h2 id="md-intro-2">Intro<a class="heading-permalink" href="#md-intro-2"/);
  assert.match(html, /<h3 id="md-other-part">Other <em>part<\/em><a class="heading-permalink" href="#md-other-part"/);
});

test("renders single-line and fenced display math", () => {
  const html = renderMarkdown("Before\n\n$$E = mc^2$$\n\n$$\na^2 + b^2\n$$");
  assert.match(html, /<p>Before<\/p>/);
  assert.match(html, /<div class="math-display">E = mc\^2<\/div>/);
  assert.match(html, /<div class="math-display">a\^2 \+ b\^2<\/div>/);
});
