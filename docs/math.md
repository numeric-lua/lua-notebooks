# Math rendering

Notebook markdown supports a small **inline LaTeX subset**. Math segments use a
vendored DejaVu Sans font with real Greek/math glyphs; body text keeps the
notebook font. Display math uses the same font through the box-layout engine. `\mathbf`,
`\mathit`, and `\mathrm` select vendored bold/italic/regular variants.

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

Display lines of the form `$$...$$` are centered on their own row and scale
down when wider than the cell. A display
row containing exactly `\frac{a}{b}` is drawn as a small stacked fraction with a
rule, `\sqrt{x}` gets a radical/overline, and a simple
`\begin{matrix}...\end{matrix}` gets a centered grid; everything else remains
linear text. This is **not MathJax or
TeX**: there is no stacked fraction layout, matrix, or real typesetting engine. The Unicode output also depends on glyphs
available in the current LÖVR font. A future backend should render TeX to an
image/texture or use a proper math layout engine.
