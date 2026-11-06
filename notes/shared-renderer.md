# A shared renderer for the HTML report

## Why

The Ruby gem and the Python port draw the same pages: the same
index, file pages, cards and decision trees, from the same CSS and JS
assets, copied byte for byte. Only the code that writes the HTML
differs, and each port keeps its own copy of it (Ruby's `html_*.rb`,
Python's `html_*.py`). Every change to a card is made twice.

So: each port writes data, and one renderer, in JavaScript, draws
the pages from it.

## Where it runs

In the viewer's browser. A run writes static files, as now; no Node,
no Docker, nothing new at test time.

Pages open from `file://`, where a page cannot `fetch` a JSON file.
So each page's data is a script that sets a global:

```
coverage/
  index.html               shell, copied
  index.data.js            window.pathCoverage = {...}
  render.js                the renderer, copied
  style.css, settings.js, theme.js, ...   as now
  files/lib/a.rb.html      shell: <script src=a.rb.data.js>
                                  <script src=../../render.js>
  files/lib/a.rb.data.js   window.pathCoverage = {...}
```

The shell pages are identical but for their script paths. A port
writes them from one template.

## Where the master source lives

A third repo, eg `path_coverage_html`:

```
path_coverage_html/
  schema.json      the data contract
  render.js        builds the DOM from window.pathCoverage
  *.css, *.js      the assets the ports copy today
  samples/         data files, one per thorny construct
  test/            renderer tests, run in Docker (Node + headless
                   Chrome, as the puppeteer probe already does)
  bin/check_pixels.sh   moves here
```

Each port vendors a tagged copy into its own tree (`lib/.../html/`,
`src/.../html/`) with a `VERSION` file, via a `bin/sync_html.sh`.
CI diffs the copy against the tag. So the gem and the wheel still
ship everything they need, and need nothing at install time.

## The data contract

One data file per page. A file page's:

```
{
  "schema": 1,
  "path": "lib/a.rb",
  "lines": ["def f(a)", ...],
  "tokens": [[line, col, length, "k|n|s|c|t"], ...],
  "decisions": {
    "2:2": { "operator": "if", "counts": [...], "tree": {...} }
  },
  "cards": {
    "1:0": { "name": "f", "first": 1, "last": 7, "rows": [...] }
  },
  "tree": { "1:0": { "2:2": { "parent": null, ... } } },
  "reached": { "3:4": 1 },
  "totals": { "methods": [taken, possible] }
}
```

- `tokens`: syntax colouring stays in each port, as only it can lex
  its language. The renderer only paints ranges.
- `decisions[...].tree`: the decision's grid as the port's decision tree builds it
  today (operator, cells per column, operands, arm labels, texts).
  This is the largest piece of per-language logic, and it stays in
  the port: the renderer draws cells, it does not work out outcomes.
- `cards` and `tree`: as the JSON report already writes them,
  sliced to the file and keyed by `line:col` without the path.
- `schema`: the renderer refuses a data file of another schema, so a
  stale vendored copy fails loudly, not silently wrong.

The index's data: one row per file with its totals, and the groups
and tabs it shows now.

The rule for the split: a port computes, the renderer draws. Any
number the console also prints (totals, complexity) is computed in
the port, so the two never disagree.

## What the tree adds to the renderer

Cards today are flat rows. With `tree` the renderer can:

- indent a row under its parent's arm, as the code is nested;
- label the arm a row is in (then, else, when);
- on hover, mark the parent's columns (`on`) that reach the row;
- for an untaken row, show which parent paths would reach it, so
  the gap reads as "take a's then arm first".

## What moves out of each port

Ruby: `html_branch`, `html_cards`, `html_cells`, `html_file`,
`html_index`, `html_index_head`, `html_labels`, `html_methods`,
`html_nav`, `html_statements`, `html_tabs`, `html_template`,
`html_tree`. `html_syntax` shrinks to a token emitter. `html_report`
shrinks to writing shells and data files.

Python: the matching `html_*.py` modules, likewise.

Each port then tests its data files (exact JSON), not HTML. The DOM
is tested once, in the renderer's repo, against its samples.

## Steps

1. Write `schema.json` from what Ruby's pages draw today.
2. Ruby writes each page's data file beside its HTML, unchanged.
3. Build `render.js` until it draws Ruby's pages the same:
   `check_pixels.sh` says same for every demo screenshot.
4. Ruby switches to shells plus data; its `html_*` modules go.
5. Python writes the same data files; its `html_*` modules go.
6. The demo and the README's card images come from the renderer
   repo's samples.

## Open questions

- A page with JS off is blank. Acceptable for a coverage report?
- Large files: one data file per page keeps pages fast, but a
  `.data.js` beside every `.html` doubles the file count.
- Should the renderer own the complexity fold over `tree`, or the
  ports? The rule above says the ports; the console needs it too.
- Rows that the tree treats as plain sequence (`rescue` arms,
  `while` and `each` bodies) draw unindented until those are decisions.
