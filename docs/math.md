# Math rendering

Notebook markdown supports a small **inline LaTeX subset**, rendered to readable
text using the LÖVR font. The font lacks Greek/math glyphs, so symbols use ASCII
names (`alpha`, `pi`, `<=`, `inf`).

```markdown
Energy: $E = mc^2$
Symbols: $\alpha + \beta = \pi$
Fraction: $\frac{1}{2}$
Root: $\sqrt{x}$
```

Supported:

- common Greek letters;
- `\sum`, `\int`, `\infty`, `\pm`, `\times`, `\cdot`, comparison arrows;
- `\sqrt{...}` and simple `\frac{a}{b}`;
- superscripts/subscripts for digits and a few letters;
- inline `$...$` only.

Display lines of the form `$$...$$` are centered on their own row, but they
still use the same linear text layout as inline math. This is **not MathJax or
TeX**: there is no stacked fraction layout, matrix, or real typesetting engine. The Unicode output also depends on glyphs
available in the current LÖVR font. A future backend should render TeX to an
image/texture or use a proper math layout engine.
