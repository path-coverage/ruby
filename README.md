# <img src="https://avatars.githubusercontent.com/u/353243247?v=4" alt="" width="32" height="32"> path-coverage/ruby

[![Gem Version](https://img.shields.io/gem/v/path_coverage)](https://rubygems.org/gems/path_coverage)
[![Downloads](https://img.shields.io/gem/dt/path_coverage)](https://rubygems.org/gems/path_coverage)
[![License](https://img.shields.io/github/license/path-coverage/ruby)](LICENSE.md)

Path coverage for Ruby, to run alongside SimpleCov's line and branch
coverage.

Status: sites cover `&&`, `||`, `and`, `or`, the ternary `?:`,
`if`/`elsif`/`else` and `unless` (modifiers included), `case`/`when`
with a subject, and the block methods `any?` `all?` `none?` `find`
`detect` `find_index` `take_while` `select` `filter` `reject`
`partition` `count` `filter_map`, the writes `||=` and `&&=`, and `&.`
safe-navigation chains. Method paths cover every site at a method's
top level.
More decisions hidden inside calls come next (see Roadmap).

Demo: https://path-coverage.github.io/ruby/ shows the HTML report
for the mock source tree in `demo/`. `make demo` builds and opens the
same report locally.

## Overview

A *site* is one decision in your code: an `&&`, `||`, `if`,
`case`, `&.` chain, `||=`, or a block method such as `any?`.
Each way it can go is a *path*. For example

```ruby
name.size > 2 && name.ascii_only?
```

has three paths: true then true, true then false, and false
alone, as `&&` then skips its right side.

Line and branch coverage can be 100% while a path was never
taken. path_coverage counts how often each path was taken:
within each site, and within each method, through its sites.

As the run exits it writes its report:
- `path_coverage.json`, for AIs and other tools.
- `path_coverage.source.json`, what drawing each file's code needs.

The HTML report, for people, is drawn from those two by
[html-reporter](https://github.com/path-coverage/html-reporter):
`index.html`, a sortable row per covered file with its paths taken
within each method, and a page per file with its cards.

```sh
docker run --rm -v "$PWD/coverage:/paths" ghcr.io/path-coverage/html-reporter /paths
```

## Reading the HTML

Clicking a `def` line on a file's HTML page opens that method's
*card* to its left. One card is always open.

A card has a row for each site in the method, by `line:col`,
with its counts of paths not taken and taken.

Clicking a row's `▼` opens it:
- on the left is the site's code, as a tree.
- on the right is one column for each possible path through it.
  - the column's head is `≀0` for a path never taken, and `≀*`
    for one taken (hover for its count). Look for zeros!
  - the symbols in a column line up with the tree's rows, and
    are explained below.

Hovering over code in the open card's method opens the tree holding
that code, its row lit, or, for a `return` or `raise`, lights its row.
A long piece of code scrolls within its row.

### Boolean: `T` `F`

Many parts of a site, such as `name.size > 2`, are true or false.

![A file's page: line 2, name.size > 2 && name.ascii_only?, its card open to its left](docs/example-outcome.png)

- `T` the expression was true.
- `F` the expression was false.

In this example, there was no test which exercised the path where `name.size > 2` was `true`, and
`name.ascii_only?` was `false`.

### Unreachable: blank

Some parts of a site are not always evaluated.

![A file's page: line 2, @x = dee || dum, its card open to its left](docs/example-unreachable.png)

- "blank" the expression is never evaluated.

In the second column `dee` was `T`, so because of `||`'s short-circuiting, `dum` is never evaluated.

### Taken: `✓`

A `?:` takes one of its arms.

![A file's page: line 2, paid ? 'paid' : 'due', its card open to its left](docs/example-taken.png)

- `✓` marks the column whose path goes to that arm

The `paid` row is the `?:`'s predicate, `T` or `F`. Below it is one row
per arm, `? 'paid'` and `: 'due'`. The first column, `paid` false, never
taken, goes to `: 'due'`; the second, `paid` true, to `? 'paid'`.

An `if`, `unless`, `case` or `||=` shows no arm rows: which arm a path
takes follows from its predicate, and the code in an arm is a row of
its own on the card.

### Navigation: `∅` `●`

`&.` skips the rest of its chain when its receiver is nil.

![A file's page: line 2, user&.account&.owner, its card open to its left](docs/example-nil.png)

- `∅` the receiver was nil, so `&.` skipped the rest of the chain.
- `●` the receiver was not nil, so `&.` made the call.

In this example, there was no test which exercised the path where
`user` was nil.

### Count: `0` `1` `*`

A block method can call its block on any number of items.

![A file's page: line 2, ids.any? { |id| id.odd? }, its card open to its left](docs/example-count.png)

- `0` the block was called with no items.
- `1` the block was called with one item.
- `*` the block was called with two or more items.

In this example, there was no test which exercised the path where
the block was called with two or more items and every answer was
`false`.

### Both: `TF`

A block's answers can differ from item to item.

![A file's page: line 2, ids.select { |id| id.odd? }, its card open to its left](docs/example-both.png)

- `T` every answer of the block was true.
- `F` every answer of the block was false.
- `TF` the block's answers were both true and false.

In this example, there was no test which exercised the path where
the block was called with two or more items and every answer was
`false`.

### Lots of paths!

Ruby code can be very compact so short expressions can generate lots of paths!

![A file's page: line 2, if user&.admin? && ids.select { |id| id.odd? }.any?, its card open to its left](docs/example-overview.png)


## Getting started

```ruby
# test coverage config, before any application code is required
require 'simplecov'
require 'path_coverage'
SimpleCov.start do
  # ...
end
PathCoverage.start do
  root APP_DIR                 # cover globs and site names are relative to it
  cover 'source/**/*.rb'       # each matching file is instrumented as it loads
  cover 'test/**/*.rb'         # more than one cover glob may be given
  skip 'source/vendor/**/*.rb' # except these, though a cover glob matches them
  coverage_dir '/tmp/coverage' # where path_coverage.json is written
  report :gaps, :summary       # the reporters run at exit (default :gaps);
                               # also :post
  group 'code', 'source/**/*.rb' # each group a tab of its own on index.html
  group 'test', 'test/**/*.rb'
  ignore '&&='                 # operators whose sites are not measured
  treat 'name', as: :present   # a call to name is never nil
  treat 'any?', as: :nonempty  # any? is true when its receiver has items
end
```

## Use when you cannot edit the code!

A run whose code cannot be changed, such as a script in a `docker build`
step, can be covered from its environment alone:

```sh
RUBYOPT=-rpath_coverage/auto
PATH_COVERAGE_ROOT=/app                   # root
PATH_COVERAGE_COVER=src/**/*.rb,lib/*.rb  # cover, comma-separated
PATH_COVERAGE_SKIP=src/vendor/**/*.rb     # skip, comma-separated, optional
PATH_COVERAGE_DIR=/tmp/paths              # coverage_dir
PATH_COVERAGE_COLLECTOR=http://host.docker.internal:4570/runs
```

This starts with `report :post`. With no `PATH_COVERAGE_COLLECTOR` it
starts nothing and prints nothing, so an image can set `RUBYOPT` for every
run and measure only those given a collector.

The gem's `path_coverage_collector` command is that collector. It saves
each report POSTed to it as a numbered file, and once every run is done
their gaps and summary print as one report (runs merged this way have
no HTML report):

```sh
path_coverage_collector 4570 /tmp/paths/runs   # until sent TERM
```

- A report is saved before it is answered 200, so a 200 means it is on
  disk. A report cut short, eg by a sender dying mid-send, is answered
  400 and not saved. One that cannot be saved is answered 500.
- `GET /alive` answers 200 while the collector runs.
- `GET /ready` answers 200 when its dir is writable, 503 when not. Wait
  for it before starting the runs.
- On TERM it stops accepting connections, finishes the report in hand,
  and exits 0.

```ruby
runs = Dir['/tmp/paths/runs/*.json']
PathCoverage::Render.from_json(config, runs)
```

## What a run reports

As the process exits:

- `path_coverage.json` is always written to `coverage_dir`: every site
  of every covered file, with each operand's true and false counts under
  `sites`, each site's paths under `paths`, each method's card under
  `cards`, how each card's rows nest under `tree`, the statements
  reached under `reached`, and the paths taken
  of all possible under `totals`, as [taken, possible]: `decisions`,
  `methods`, and, with groups, each group's
  own under `groups`, eg `"groups": {"code": {"decisions": [481, 567]}}`.
  It also names the kinds of site measured under `kinds`, any `ignored`
  operators and `treats`, and any paths taken that a treatment rules
  out under `outside`.
  It is the base the other reporters read, so they can also be run
  later, in another process, from
  it alone: `PathCoverage::Render.from_json(config)`, where `config` is a
  `PathCoverage::Configuration` built from the same settings block.
  Given several runs' reports, `Render.from_json(config, paths)` adds
  their counts together first, so the report shows only the gaps that
  every run left. A report whose kinds, `ignored` or `treats` differ
  from `config`'s is refused, as its sites list their paths
  differently.
- `path_coverage.source.json` is always written beside it: each
  covered file's lines and their coloured tokens, and where each site
  is and its fold's rows, so html-reporter can draw the pages without
  parsing Ruby.
- `:gaps` prints one line per site path never taken, in manifest
  order, naming the outcome of each leaf on it:

```text
source/kata.rb:3:23 path never taken: `ok?(id)` true, `new?(id)` false
source/kata.rb:4:24 never reached
```

### Decisions

A site is named by the `path:line:column` where it starts, the path
relative to `root`; but an `if` or `unless` at its keyword, a `?:` at
its `?`, and a block method's call at its method, so no two sites
share a name. A site in a covered file the run never loaded is still
reported, as `never reached`.

A path is the outcome of each leaf one evaluation of the site reached, in
order; a leaf that short-circuiting skipped is not on it. Each leaf is
quoted as a Markdown code span, on one line, its fence one backtick longer
than any run of backticks inside it. The gap lines are for people; a tool
should read the JSON, whose `paths` give each site's leaves as
`line:column` spans, and each possible path with its count:

```json
"paths": {
  "source/kata.rb:3:23": {
    "leaves": [["3:23", "3:30"], ["3:34", "3:42"]],
    "taken": [
      { "path": [true, true], "count": 2 },
      { "path": [true, false], "count": 0 },
      { "path": [false, null], "count": 1 }
    ]
  }
}
```

A site is an outermost condition. Its leaves are numbered left to right
across the whole of it, nested conditions included. A condition inside a
block is a site of its own.

A ternary is a site even when its predicate is a single leaf. An arm
holding a condition of `&&`, `||`, `and`, `or` or `?:` is part of the
ternary's site, its leaves numbered after the predicate's, so the site's
paths run through whichever arm the predicate picks. Any other arm, like a
block, is not part of it, though a condition inside it is a site of its
own.

An `if` or an `unless`, a modifier included, is a site too, even when
its predicate is a single leaf: its predicate nests in it, an `&&` there
being no site of its own, and its `then` and `else` arms are plain, as
they are statements; an `unless` takes its `then` arm when its predicate
is false. It is named at its keyword, and its extent is its keyword to
the end of its predicate, so a site inside an arm keeps its own button.
An `elsif` is a site of its own.

A `case` with a subject is a site whose leaves are its `when` patterns,
tried in order until one matches. Each pattern is wrapped in a stand-in
whose `===` calls the pattern's `===` once, exactly as the `case` would,
and notes whether it matched. A `case` with no subject, or with a splat
among its patterns, is no site.

A call to `any?` `all?` `none?` `find` `detect` `find_index`
`take_while` `select` `filter` `reject` `partition` `count` or
`filter_map`, with no arguments and a block of one expression, is a site
named at its method. Its item count is noted from the block's own calls,
so the receiver is never asked its size, which could consume a sequence
that can be read only once.

A `||=` or `&&=` write is a site, whatever its target: a variable of any
kind, a constant, an attribute (`self.size ||= n`) or an index
(`store[key] ||= key.upcase`). Its one leaf is its target, and its right
side is an arm, run when the target is false for `||=`, true for `&&=`,
as an `unless` or an `if` runs its arm. The target is never read again,
since reading `store[key]` could call a method twice: its outcome follows
from whether the right side ran. So `@clock ||= Clock.now` called only
once, as a fresh object, leaves the path with `@clock` true a gap.

A `&.` chain is a site, named where it starts. Its leaves are the
receivers of its `&.` calls. `false` counts as not nil, as `&.` calls on
it.

A chain inside a condition, eg `ok?(id) && user&.admin?` or
`if user&.admin?`, folds into its site, as one expression: its value is
one more leaf, true or false, reached when every receiver is not nil. A
write through `&.`, eg `box&.size ||= 3`, is no site, as a nil `box`
skips it whole and its target is never looked at.

A chain of one operator is flat; a change of operator, by precedence or by
parentheses, nests. Parentheses are not part of the tree, since they decide
nothing.

A leaf whose form allows one outcome only needs only to be evaluated: a
path needing its other outcome is impossible, not a gap. `Foo.new`,
literals (`'s'`, `1`, `:k`, `[]`, `{}`, `true`) and lambdas can only be
truthy, as can `$stdout` and `$stderr`, which Ruby refuses to set to nil
or false. Other globals, `$stdin` among them, can be either, as can
constants, since one can hold nil or false (`VERBOSE = false`). `nil` and
`false` can only be falsy:

```ruby
@clock = options[:clock] || MonotonicClock.new  # leaf 1: never evaluated, or no gap
```

Any other leaf, a call among them, is taken to have either outcome, as its
form alone cannot say which it returns. So a call that never returns nil
or false still leaves a path needing it falsy, which no test can take:

```ruby
methods: paths && methods_of(path, methods, paths)  # [true, false] impossible
methods: paths ? methods_of(path, methods, paths) : nil  # the same, no such path
```

Written as a choice, the same code has no such path. Reporting a gap that
cannot be closed is the lesser error than hiding one that can.

### Methods

Each method has a card, named by the `path:line:column` of its `def`,
with a row for each statement that shapes its paths: each site, and
each `return` or `raise`, which ends a path. Any other statement, eg
`x = 1`, runs exactly when what holds it does, so is no row. A site's
row counts its paths; a `return` or `raise` row is one path, taken
when it is reached. A method's total adds up its rows. Its title says
how many times it was called, so a method never called is a gap,
even one with no rows. A file's code outside any method gets a card
of its own.

The JSON report's `cards` hold each card's rows, its `ways` (the ways
one call can go through it) and its `calls`:

```json
"cards": {
  "label.rb:1:0": {
    "name": "label", "first": 1, "last": 7, "ways": 2, "calls": 1,
    "rows": [
      { "at": "2:02", "top": "if", "paths": 2, "taken": 1, "site": "label.rb:2:2" },
      { "at": "3:04", "top": "return", "paths": 1, "taken": 1, "site": null },
      { "at": "5:04", "top": "return", "paths": 1, "taken": 0, "site": null }
    ]
  }
}
```

Its `tree` says how those rows nest, by file, then card, then row.
A row inside a site names that site as its `parent`, the arm it is
`in`, and `on`, the indices of the parent's paths that run it, in the
order `paths` lists them. A row at the method's top has none of these.

```json
"tree": {
  "label.rb": {
    "1:0": {
      "2:2": { "parent": null, "in": null, "on": null, "leaf": null, "gives": null },
      "3:4": { "parent": "2:2", "in": "then", "on": [0], "leaf": null, "gives": null },
      "5:4": { "parent": "2:2", "in": "else", "on": [1], "leaf": null, "gives": null }
    }
  }
}
```

A row inside one of its parent's leaves names that `leaf`, by index.
A row that is the whole of that leaf, like the `any?` here, also
`gives` the leaf's outcome on each of its own paths, `null` where not
known:

```ruby
def led?(xs)
  xs.any? { |x| x.odd? } || xs.empty?
end
```

```json
"2:5": { "parent": "2:2", "in": null, "on": [0, 1, 2], "leaf": 0,
         "gives": [false, true, false, true, false] }
```

Its 5 paths are 0 items, then 1 item and 2+ items, each with a last
answer true or false.

### Reporters

- `:post` sends the JSON report, as an HTTP POST, to the url set by
  `collector 'http://...'`. It is for a run whose own files are thrown
  away, such as a failing `docker build` step. It prints nothing, never
  goes through an `http_proxy`, and gives up in silence on a collector
  that cannot be reached or does not answer within a second, so the
  run's output and exit status are unchanged.
- `:summary` prints each total as SimpleCov prints its line and branch
  coverage:

```text
Path coverage within decisions: 527 / 631 (83.52%)
Path coverage within methods: 44 / 52 (84.62%)
```

  With groups, each group is a heading, its own totals indented under it,
  and there is no total over every group.

```text
code:
  Path coverage within decisions: 481 / 567 (84.83%)
  Path coverage within methods: 41 / 49 (83.67%)
test:
  Path coverage within decisions: 65 / 84 (77.38%)
  Path coverage within methods: 3 / 3 (100.00%)
```

## How it works

At load time each covered file is read and parsed once, with Prism. The
parse gives the manifest: each site's condition tree and the byte range of
each of its leaves. The rewriter then inserts a record call around each
leaf, and a leave call around the whole site, whose first argument enters
it, without parsing again, and the result is compiled in place of the
file:

```ruby
ok?(id) && new?(id)
# compiles as
PathCoverage.leave(PathCoverage.enter("k.rb:2:2", 2), PathCoverage.record("k.rb:2:2", 0, ok?(id)) && PathCoverage.record("k.rb:2:2", 1, new?(id)))
```

An `if` site's leave call wraps its predicate alone, as its path is
decided there, so an arm that returns or raises still counts it.
Each statement that is no site gets a reach call before it, counting
its run, for its card's row.

A command call such as `ok? id` (after `and`) is not valid as a bare
argument, so that leaf alone gets parentheses of its own, and so does a
whole `and` or `or` inside its leave call. Nothing else does:
parentheses make a statement, and a statement on a continuation line gives
that line a line-coverage count of its own, which changes SimpleCov's line
totals. So a command call, or an `and` or `or`, written over several lines
can add to SimpleCov's relevant lines; nothing else does.

`record` counts whether its value was truthy or falsy, and notes it on the
site's current path; `enter` starts that path, and `leave` counts it.
Each returns its value unchanged, so short-circuiting and the value of
the expression are preserved. Paths are kept per fiber, so threads never
mix their outcomes; an evaluation cut short by a raise counts no path,
so no path is ever claimed that was not taken. Only text is inserted,
never a newline, so backtrace line numbers still match the file. The
rewrite happens in memory; no file on disk changes.

At exit the manifests parsed during the run are reused; only covered files
the run never loaded are read and parsed then.

## Ignoring and treating

`ignore '&&=', '||='` stops `&&=` and `||=` writes being measured.
A site inside such a write is still measured, eg the `a && b` in
`@m ||= a && b`. Ignoring `&&` does not ignore `and`, nor does ignoring
`||` ignore `or`. The summary and `index.html` list what is ignored.

`treat` tells path_coverage what you know about a method, so paths that
cannot happen are not listed as gaps. Add `in: 'source/models/**'` to
limit a treatment to the files that glob matches.

- `treat 'name', as: :present`: a call to `name` is never nil, so
  `user.name&.size` has no path with `user.name` nil.
- `treat 'any?', as: :nonempty`: `x.any?` is true exactly when `x` has
  items. When `x` is a call to `select`, `reject`, `filter`,
  `filter_map`, `partition` or `take_while`, the path that call took
  often decides whether it kept any items. Paths where `any?` disagrees
  with that are not listed, eg `ids.select { |i| i.odd? }.any?` true
  with `ids` empty.

A run where a treatment turns out to be wrong is reported:

```text
source/user.rb:4:9 path taken that a treatment rules out: `user.name` nil
```

## Roadmap

- decisions hidden inside calls, each with its own outcome classes:
  - `one?`, whose last answer does not decide it, and block methods
    with blocks of more than one expression
  - `fetch(k, default)`, `dig`, `Hash#[]` with a default: present vs default
  - `x || default` in value context: nil vs not nil
  - `x rescue y` modifier: raised vs not raised
  - `case` with no subject, and `case`/`in` patterns
  - regex matches: nil vs MatchData
- `treat 'methods_of', as: :truthy`, so each call to it counts as a
  leaf that is only truthy, as `Foo.new` is, and a run where it returns
  nil or false is reported. Later, treatments could come from the
  project's RBS signatures (`sig/*.rbs`) too.
- exceptions the code itself names: a `begin` or `def` with `rescue`
  clauses as a site, like a `case`, whose paths are no raise and each
  clause that rescued, eg `rescue IOError` never taken. Branch coverage
  ignores `rescue`, and tests reach these paths with real input. A raise
  that nothing names, from any call, stays out, as every leaf would gain
  a third outcome that only fault injection could take.
- an evaluation that raised part way through a site, eg
  `ok?(id) && fetch(id)` where `fetch` raises, reported as a path that
  raised rather than dropped as unfinished.
- complexity maximums, reported and gated, since the possible paths
  count how much there is to test, not only how much was tested. A
  file's total measures its size, so each is a maximum over smaller
  parts:
  - paths in one decision, eg 6 for a `select` block
  - paths through one method's decisions, eg 2 top-level ifs give 4
  - paths within each decision, summed over every decision in one
    method, nested ones included, eg decisions of 2, 3 and 15 paths
    sum to 20. Every method has one, and it grows as the method gains
    conditions, where the paths through a method multiply.

## Constraints

- CRuby only: the hook is `RubyVM::InstructionSequence.load_iseq`.
- Ruby 3.2 or later, for `String#bytesplice`.
- That hook has a single slot, which Bootsnap also uses, so the two cannot
  both be active in one process.

## Development

`make all` runs, in a Docker image built from the repo's `Dockerfile`:

- `make lint`: rubocop over `lib/`, `test/` and `bin/` alike
- `make test`: the tests, with path_coverage measuring its own `lib/` and
  `test/`, then a check that SimpleCov's report has zero missed lines and
  branches in both the code and the tests, and that every path within the
  tests' methods was taken, within the bounds in
  `test/coverage_metrics_params.json` (a path bound is eg
  `test.paths.methods.missed`, and a missing path report denies it)
  (`make test tids='6D1K'` runs only matching tests, and skips the check)
- `make test_check`: shunit2 tests showing that a breached bound fails the
  check with a non-zero exit

Each run prints its seed; `SEED=n make test` replays that run's order of
files and tests. When the coverage check fails, it names each line and
branch missed.

A run ends with each group, code and test, as a heading over its four
figures, SimpleCov's and path_coverage's together, then where each report
is, each with a code and a test tab, then the check's verdict:

```text
code:
  Line coverage: 1270 / 1270 (100.00%)
  Branch coverage: 321 / 321 (100.00%)
  Path coverage within decisions: 481 / 567 (84.83%)
  Path coverage within methods: 41 / 49 (83.67%)
test:
  Line coverage: 2250 / 2250 (100.00%)
  Branch coverage: 43 / 43 (100.00%)
  Path coverage within decisions: 65 / 84 (77.38%)
  Path coverage within methods: 3 / 3 (100.00%)
SimpleCov report: .../reports/index.html
PathCov report: .../reports/paths/index.html
coverage: ALLOWED
```

`bin/check_coverage_metrics.rb` prints the groups, reading SimpleCov's
figures from `reports/coverage_metrics.json` and path_coverage's from the
`totals` in `reports/paths/path_coverage.json`; SimpleCov's own console
lines, totals over every group, are silenced. The tool measuring paths is
a copy of `lib/` renamed `PathCoverageSelf` (`test/self_coverage.rb`), so
the tests start and restart `PathCoverage` as always. SimpleCov's figures
for `lib/` are the same with it as without.

`make demo` (not part of `make all`) runs `demo/run.rb` through
`bin/build_demo.sh`, writing the report to `site/` and opening it. The
Pages workflow (`.github/workflows/pages.yml`) runs the same script on
each push to `main` and publishes `site/`.

`bin/capture_card_images.sh` runs the examples in `demo/cards/` and
saves this README's screenshots, `docs/example-*.png`, with headless
Chrome. Run it again whenever the card's look changes.

