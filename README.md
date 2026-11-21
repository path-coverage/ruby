# <img src="https://avatars.githubusercontent.com/u/353243247?v=4" alt="" width="32" height="32"> path-coverage/ruby

Path coverage for Ruby, to run alongside SimpleCov's line and branch
coverage.

[![Gem Version](https://img.shields.io/gem/v/path_coverage)](https://rubygems.org/gems/path_coverage)
[![Downloads](https://img.shields.io/gem/dt/path_coverage)](https://rubygems.org/gems/path_coverage)
[![License](https://img.shields.io/github/license/path-coverage/ruby)](LICENSE.md)

- [Overview](#overview)
- [Getting started](#getting-started)
- [Ignoring and treating](#ignoring-and-treating)
- [Use when you cannot edit the code!](#use-when-you-cannot-edit-the-code)
- [What a run reports](#what-a-run-reports)
- [How it works](#how-it-works)
- [Roadmap](#roadmap)
- [Constraints](#constraints)
- [Development](#development)

## Overview

A *decision* is a choice in your code, eg an `&&`, `||`, `if`,
`case`, etc. Each way it can go is a *path*. For example

```ruby
def discount(member, coupon)
  member || coupon ? 10 : 0
end
```

has three paths: a member, a non-member with a coupon, and
neither. Tests calling `discount(true, nil)` and
`discount(false, nil)` cover every line and both branches of the
`?:`, yet no test ever tried a coupon.

Line and branch coverage can be 100% while a path was never
taken. path_coverage counts how often each path was taken:
alone, each decision's paths on their own, and combined, through
each method's decisions.

As the run exits it writes its report as two JSON files:
- `path_coverage.json`, for AIs and other tools.
- `path_coverage.source.json`, what drawing each file's code needs.

## Getting started

```ruby
# test coverage config, before any application code is required
require 'simplecov'
require 'path_coverage'
SimpleCov.start do
  # ...
end
PathCoverage.start do
  root APP_DIR                   # cover globs and decision names are relative to it
  cover 'source/**/*.rb'         # each matching file is instrumented as it loads
  cover 'test/**/*.rb'           # more than one cover glob may be given
  skip 'source/vendor/**/*.rb'   # except these, though a cover glob matches them
  coverage_dir '/tmp/coverage'   # where path_coverage.json is written
  report :gaps, :summary         # the reporters run at exit (default :gaps);
                                 # also :ways and :post
  group 'code', 'source/**/*.rb' # each group its own totals
  group 'test', 'test/**/*.rb'
  ignore '&&='                   # operators whose decisions are not measured
  max_paths 4096                 # list each method's paths up to this many
                                 # (the default; at most 65536)
  loops                          # count each loop as a decision: 0 items
                                 # or 1+ items (off by default)
end
```

## Ignoring and treating

`ignore '&&=', '||='` stops `&&=` and `||=` writes being measured.
A decision inside such a write is still measured, eg the `a && b` in
`@m ||= a && b`. Ignoring `&&` does not ignore `and`, nor does ignoring
`||` ignore `or`. The summary and the JSON report list what is
ignored.

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
  with every answer false.

A run where a treatment turns out to be wrong is reported:

```text
source/user.rb:4:9 path taken that a treatment rules out: `user.name` nil
```

### Not analysing a block

Sometimes a block of code is not worth testing path by path, for example
logging. Put `# path: disable` before the block and `# path: enable` after
it. The lines between them still run, but they are not analysed: any
decision in them is ignored, and they add no paths to the method they
are in.

The line straight after `# path: disable` must start with `# reason:` and
say why the block is not analysed:

```ruby
def ship(order, log)
  if order[:express]
    order[:days] = 1
  end
  # path: disable
  # reason: logging is not under test
  if log.verbose?
    log.lines << order[:id]
  end
  # path: enable
  order
end
```

Without the `# path: disable` and `# path: enable` comments, `ship()` has
4 paths: each `if` can be true or false. With them, the second `if` is
ignored, so `ship()` has 2 paths: `order[:express]` true, and
`order[:express]` false.

Only a real comment that is the whole of its line is a marker. The same
text inside a string, eg a heredoc, is just text: it disables nothing,
and is never refused.

```ruby
HELP = <<~TEXT
  # path: disable
TEXT
# a heredoc, not a comment: the methods below are still analysed
```

Each of these is refused, with the file and line it is on:

- a `# path: disable` without a `# reason:` line straight after it
- a `# path: disable` without a `# path: enable` after it
- a statement that starts between the two comments and ends after the
  `# path: enable`

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
each report POSTed to it as a numbered file; once every run is done,
report them as one with `path_coverage_report`, below.

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

### Reporting saved runs

Once every run is done, report them as one with `path_coverage_report`:

```text
path_coverage_report [--loops] [--max-paths N] SOURCE_ROOT GLOBS REPORT_DIR RUN_JSON...
```

- SOURCE_ROOT  the directory holding the covered source
- GLOBS        comma-separated globs of the covered files, relative to SOURCE_ROOT
- REPORT_DIR   the directory it writes its report into
- RUN_JSON...  one or more saved runs' JSON files, space-separated, eg runs/*.json
- --loops      count each loop as a decision: 0 items or 1+ items
- --max-paths  fail each method with more than N paths (default 4096, at most 65536)

With `--loops`, a loop counts as a decision only when its body has a
statement that runs first on each pass. These loops never do:

```ruby
x += 1 while x < 9          # a modifier loop: its body is written first
lines.each { }              # an empty loop
urls.each do |url|          # a loop whose only statements are rescued
rescue Timeout::Error
  retry_later(url)
end
```

It exits 0 when every path is taken, and 1 when any is not.

Every path taken:

```text
$ path_coverage_report /app 'lib/**/*.rb' report runs/*.json
Paths: 2 / 2 (100.00%)
Functions over --max-paths=4096: 0
```

Some paths untested, and a method over --max-paths:

```text
$ path_coverage_report --max-paths 8 /app 'lib/**/*.rb' report runs/*.json
lib/fees.rb:2 fee() has 16 paths, more than --max-paths allows.
Split it into smaller functions.
lib/orders.rb:2 total() has 1 untested path.
Add tests that take each of these paths:
  1. line 5 `order[:paid]` false
Paths: 1 / 2 (50.00%)
Functions over --max-paths=8: 1
```

Each run's JSON names the kinds of decision it measured. A version that
measures other kinds lists a decision's paths differently, so a run whose
kinds differ from those of the installed version is refused. So is a run
made with `ignore` or `treat`, as the command takes neither.

## What a run reports

As the process exits:

- `path_coverage.json` and `path_coverage.source.json` are always
  written to `coverage_dir`. Their keys, with examples, are in
  [path-coverage/schemas](https://github.com/path-coverage/schemas#path_coveragejson).
  `path_coverage.json` is the base the other reporters read, so they can also be run
  later, in another process, from
  it alone: `PathCoverage::Render.from_json(config)`, where `config` is a
  `PathCoverage::Configuration` built from the same settings block.
  Given several runs' reports, `Render.from_json(config, paths)` adds
  their counts together first, so the report shows only the gaps that
  every run left. A report whose kinds, `ignored` or `treats` differ
  from `config`'s is refused, as its decisions list their paths
  differently.
- `:gaps` prints one line per decision path never taken, in manifest
  order, naming the outcome of each leaf on it:

```text
source/kata.rb:3:23 path never taken: `ok?(id)` true, `new?(id)` false
source/kata.rb:4:24 never reached
```

### Decisions

A decision is named by the `path:line:column` where it starts, the path
relative to `root`; but an `if` or `unless` at its keyword, a `?:` at
its `?`, and a block method's call at its method, so no two decisions
share a name. A decision in a covered file the run never loaded is still
reported, as `never reached`.

A path is the outcome of each leaf one evaluation of the decision reached, in
order; a leaf that short-circuiting skipped is not on it. Each leaf is
quoted as a Markdown code span, on one line, its fence one backtick longer
than any run of backticks inside it. The gap lines are for people; a tool
should read the JSON, whose `paths` give each decision's leaves as
`line:column` spans, and each possible path with its count.

A decision is an outermost condition. Its leaves are numbered left to right
across the whole of it, nested conditions included. A condition inside a
block is a decision of its own.

A ternary is a decision even when its predicate is a single leaf. An arm
holding a condition of `&&`, `||`, `and`, `or` or `?:` is part of the
ternary's decision, its leaves numbered after the predicate's, so the decision's
paths run through whichever arm the predicate picks. Any other arm, like a
block, is not part of it, though a condition inside it is a decision of its
own.

An `if` or an `unless`, a modifier included, is a decision too, even when
its predicate is a single leaf: its predicate nests in it, an `&&` there
being no decision of its own, and its `then` and `else` arms are plain, as
they are statements; an `unless` takes its `then` arm when its predicate
is false. It is named at its keyword, and its extent is its keyword to
the end of its predicate, so a decision inside an arm keeps its own button.
An `elsif` is a decision of its own.

A `case` with a subject is a decision whose leaves are its `when` patterns,
tried in order until one matches. Each pattern is wrapped in a stand-in
whose `===` calls the pattern's `===` once, exactly as the `case` would,
and notes whether it matched. A `case` with no subject, or with a splat
among its patterns, is no decision.

A call to `any?` `all?` `none?` `find` `detect` `find_index`
`take_while` `select` `filter` `reject` `partition` `count` or
`filter_map`, with no arguments and a block of one expression, is a decision
named at its method. Its paths are its block's answers: the last one for a
method that can stop early, eg `any?` true or false, and all true, all
false or both for one that calls its block with every item, eg `select`.
A call whose block was never called witnesses no path. How many items the
block was called with is a loop's question, asked by `loops`, so the
receiver is never asked its size, which could consume a sequence that can
be read only once.

A `||=` or `&&=` write is a decision, whatever its target: a variable of any
kind, a constant, an attribute (`self.size ||= n`) or an index
(`store[key] ||= key.upcase`). Its one leaf is its target, and its right
side is an arm, run when the target is false for `||=`, true for `&&=`,
as an `unless` or an `if` runs its arm. The target is never read again,
since reading `store[key]` could call a method twice: its outcome follows
from whether the right side ran. So `@clock ||= Clock.now` called only
once, as a fresh object, leaves the path with `@clock` true a gap.

A `&.` chain is a decision, named where it starts. Its leaves are the
receivers of its `&.` calls. `false` counts as not nil, as `&.` calls on
it.

A chain inside a condition, eg `ok?(id) && user&.admin?` or
`if user&.admin?`, folds into its decision, as one expression: its value is
one more leaf, true or false, reached when every receiver is not nil. A
write through `&.`, eg `box&.size ||= 3`, is no decision, as a nil `box`
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

Each method has a flow, named by the `path:line:column` of its `def`,
with a row for each statement that shapes its paths: each decision, each
`return` or `raise`, which ends a path, and each `next`, `break` or
`retry`, which ends a pass of its loop. Any other statement, eg
`x = 1`, runs exactly when what holds it does, so is no row. A decision's
row counts its paths; a `return` or `raise` row is one path, taken
when it is reached. A method's total adds up its rows. Its `calls`
count how many times it was called, so a method never called is a gap,
even one with no rows. A file's code outside any method gets a flow
of its own.

A `begin` or `def` with `rescue` clauses forks its flow: its body
completes, or one of its rescues runs. A rescue can run after any part
of its body, as a raise can come from any call, so which exception was
raised is not tracked. A `rescue` modifier, `x rescue y`, forks the
same way, with one rescue. With `loops`, each loop forks too, a block
method's block included: 0 items, or 1+ items, its body walked once.

The JSON report's `flows` hold each flow's rows, its `ways` and its
`calls`, and its `tree` says how those rows nest.

A method's flow counts only the paths its method can take. A
local variable the method never writes, eg a parameter, read as a
leaf outside any block, has one outcome all through a call, so

```ruby
def fee(member, big)
  return 0 if member
  total = member ? 90 : 100   # its true path: none, member is false here
  big ? total - 10 : total
end
```

the `?:` row has 1 path, not 2, its ways are 3, not 5, and Paths
combined counts 5, not 6. Paths alone, and the gap lines, still
list each decision's paths on its own. An instance variable or a
call may change between two reads, so is never taken to be the
same; nor is any local of a method calling `binding`, `eval`,
`send` or the like. A path taken that the method rules out is
counted, and printed:

```text
flip.rb:5:11 path taken that its method rules out: `member` true
```

### Reporters

- `:ways` prints, for each method with a path through it that no run
  took, the choices a test must make to take each one, every leaf by its
  source text; a loop is named by its line and how many items it ran,
  and a rescue by its line and whether its body completed or which
  rescue ran:

```text
lib/orders.rb:2 total() has 1 untested path.
Add tests that take each of these paths:
  1. line 5 `order[:paid]` false
```

  Every run writes these lines to `path_coverage.ways.txt` in the
  coverage dir, whichever reporters print, so a later check can show them.

- `:post` sends the JSON report, as an HTTP POST, to the url set by
  `collector 'http://...'`. It is for a run whose own files are thrown
  away, such as a failing `docker build` step. It prints nothing, never
  goes through an `http_proxy`, and gives up in silence on a collector
  that cannot be reached or does not answer within a second, so the
  run's output and exit status are unchanged.
- `:summary` prints each total as SimpleCov prints its line and branch
  coverage:

```text
Paths alone: 527 / 631 (83.52%)
Paths combined: 44 / 52 (84.62%)
```

  With groups, each group is a heading, its own totals indented under it,
  and there is no total over every group.

```text
code:
  Paths alone: 481 / 567 (84.83%)
  Paths combined: 41 / 49 (83.67%)
test:
  Paths alone: 65 / 84 (77.38%)
  Paths combined: 3 / 3 (100.00%)
```

## How it works

At load time each covered file is read and parsed once, with Prism. The
parse gives the manifest: each decision's condition tree and the byte range of
each of its leaves. The rewriter then inserts a record call around each
leaf, and a leave call around the whole decision, whose first argument enters
it, without parsing again, and the result is compiled in place of the
file:

```ruby
ok?(id) && new?(id)
# compiles as
PathCoverage.leave(PathCoverage.enter("k.rb:2:2", 2), PathCoverage.record("k.rb:2:2", 0, ok?(id)) && PathCoverage.record("k.rb:2:2", 1, new?(id)))
```

An `if` decision's leave call wraps its predicate alone, as its path is
decided there, so an arm that returns or raises still counts it.
Each statement that is no decision gets a reach call before it, counting
its run, for its flow's row.

A command call such as `ok? id` (after `and`) is not valid as a bare
argument, so that leaf alone gets parentheses of its own, and so does a
whole `and` or `or` inside its leave call. Nothing else does:
parentheses make a statement, and a statement on a continuation line gives
that line a line-coverage count of its own, which changes SimpleCov's line
totals. So a command call, or an `and` or `or`, written over several lines
can add to SimpleCov's relevant lines; nothing else does.

`record` counts whether its value was truthy or falsy, and notes it on the
decision's current path; `enter` starts that path, and `leave` counts it.
Each returns its value unchanged, so short-circuiting and the value of
the expression are preserved. Paths are kept per fiber, so threads never
mix their outcomes; an evaluation cut short by a raise counts no path,
so no path is ever claimed that was not taken. Only text is inserted,
never a newline, so backtrace line numbers still match the file. The
rewrite happens in memory; no file on disk changes.

At exit the manifests parsed during the run are reused; only covered files
the run never loaded are read and parsed then.

## Roadmap

Decisions covered now: `&&`, `||`, `and`, `or`, the ternary `?:`,
`if`/`elsif`/`else` and `unless` (modifiers included), `case`/`when`
with a subject, and the block methods `any?` `all?` `none?` `find`
`detect` `find_index` `take_while` `select` `filter` `reject`
`partition` `count` `filter_map`, the writes `||=` and `&&=`, and `&.`
safe-navigation chains. Method paths cover every decision in a method,
nested ones included, and its `rescue` clauses and modifiers.

Next:

- decisions hidden inside calls, each with its own outcome classes:
  - `one?`, whose last answer does not decide it, and block methods
    with blocks of more than one expression
  - `fetch(k, default)`, `dig`, `Hash#[]` with a default: present vs default
  - `x || default` in value context: nil vs not nil
  - `case` with no subject, and `case`/`in` patterns
  - regex matches: nil vs MatchData
- `treat 'methods_of', as: :truthy`, so each call to it counts as a
  leaf that is only truthy, as `Foo.new` is, and a run where it returns
  nil or false is reported. Later, treatments could come from the
  project's RBS signatures (`sig/*.rbs`) too.
- an evaluation that raised part way through a decision, eg
  `ok?(id) && fetch(id)` where `fetch` raises, reported as a path that
  raised rather than dropped as unfinished.
- complexity maximums, reported and gated, since the possible paths
  count how much there is to test, not only how much was tested. A
  file's total measures its size, so each is a maximum over smaller
  parts. `max_paths` already gates the paths through one method; still
  to come:
  - paths in one decision, eg 3 for a `select` block
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
  `test.paths.combined.missed`, and a missing path report denies it)
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
  Paths alone: 481 / 567 (84.83%)
  Paths combined: 41 / 49 (83.67%)
test:
  Line coverage: 2250 / 2250 (100.00%)
  Branch coverage: 43 / 43 (100.00%)
  Paths alone: 65 / 84 (77.38%)
  Paths combined: 3 / 3 (100.00%)
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

