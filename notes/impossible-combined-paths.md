# Impossible combined paths

What makes a way through a method impossible, which of those the
gem now rules out, and which it keeps.

## What combined counts

`Paths combined` adds up, over each def's card, its rows' paths.
It does not multiply them: counting whole ways needs whole-path
recording, which is not built. The card's `ways` is the
multiplied count, with nothing taken. So an impossible way shows
in two figures: `ways`, and a row path that no way through its
method can take, which `combined` counted as a gap.

Both now come from one fold, `CardWays`, over one of
`WayAlgebras`: `Counted` gives `ways`, `Labelled` the row paths on
some possible way (`CardContext`, which `combined`, the card rows'
`paths` and html-reporter's per-file figure all use), and
`Listed` the ways themselves, for the oracle. `Tallied` keeps
each way's assignment of stable leaves, and joining two ways that
give one name both outcomes yields no way.

## The oracle

`test/property/load_test.rb` Pq3L12. `MethodGrammar` with
`reuse: true` draws a leaf from the parameters already drawn half
the time, and writes three top-level statements, so guards, nested
ifs on the same parameter and repeated leaves in one decision
appear. Each method runs on every combination of its parameters;
the recorder's counts, diffed around each call, give the way it
took. The set of ways taken is the ground truth. Two assertions:
no way taken is missing from the gem's (soundness), and no way
listed is never taken (exactness).

Before: 35 of 40 seeds listed impossible ways; none missed one.
After: equal for all 40, and for 400 seeds in a one-off run.

## Classes, and what was done

- (a) a nested decision fixed by an enclosing one, eg `if a` then
  `x if a` inside: ruled out, for stable leaves.
- (b) the same leaf twice in a method, or in one decision, eg
  `a && b || a && c`: ruled out, for stable leaves.
- a guard on a stable leaf, eg `return 0 if a` then `a ? 1 : 2`:
  ruled out, as the fold already ends the ways that leave.
- a row no way reaches, eg after an unconditional raise: 0 paths.

A stable leaf (`StableLeaves`) is a read of a local variable,
outside any block, lambda or nested def, where the leaf's outcome
is its truthiness (an operand of `&&` `and` `||` `or`, or the
predicate of `if` `unless` `?:`), and that no code in the def
writes (no write, op-write, `||=`, multiple assignment, rescue
target or pattern capture, anywhere in it, blocks included), in a
def that calls none of `binding` `eval` `instance_eval`
`class_eval` `module_eval` `send` `__send__` `public_send`
`method`. Only names read by two or more such leaves matter.

Kept, deliberately:

- (c) a guard on a call, eg `return if ids.empty?` then
  `ids.any? { }` with 0 items. A call can answer differently each
  time, and `empty?` and `any?` need not agree for an arbitrary
  receiver. `treat 'any?', as: :nonempty` exists for this.
- calls of any kind, eg `order[:gift]` twice, `!a`, and instance
  variables, which any call between the two reads may change;
  constants and globals likewise.
- a local written anywhere in the def, even once before every
  read. Sound for a single top-level write before the reads, but
  not done: a later step.
- leaves of `case`/`when` (pattern matches), `&.` receivers (nil
  or not, false being not nil) and block methods (item counts).
- (d) a fold whose `?:` arm is a literal, eg `a && (b ? 1 : 2)`:
  2 of its 5 paths are impossible. Ruling them out needs the
  manifest to note each arm's truthiness, and would change the
  decision's own paths, so Paths alone and the JSON path lists
  too. Left open.

## Soundness

A derived fact can be wrong: a callee can rewrite a local through
a block's `binding` (kernel test 6rTS81), and a TracePoint or
debugger can too; a module can redefine `raise` (6rTS82). So a row
path, or a return or raise, taken though its method rules it out
is counted in combined, never dropped, and printed as a gap line:

```text
flip.rb:5:11 path taken that its method rules out: `member` true
halt.rb:6:4 reached, though its method rules it out
```

This is checked per row only. A way made of row paths each
possible on its own, but impossible together, cannot be checked
without whole-path recording; `ways` takes nothing, so nothing is
counted wrongly there.

## Numbers

Demo (`demo/run.rb`): unchanged, alone 78 / 118, combined
79 / 119, card ways summed 945, and the same gap lines. Its repeated
leaves are all calls (`order[:gift]`, `order[:pickup]`), which are
kept.

The 40 Pq3L12 methods, stable leaves off then on: card ways 335
then 160; combined possible paths 344 then 269.

Self-coverage, `make all`, before then after: code alone 789 / 789
then 836 / 836, combined 799 / 799 then 846 / 846 (the new code);
no path of the gem's own was ruled out.

## Decisions for later

- Whether gap lines should also leave out paths the method rules
  out. They follow Paths alone now, so a dev still sees eg
  `fee.rb:4:19 path never taken: member true`, which no test can
  take.
- html-reporter draws every fold column, so a ruled-out path still
  shows as a column never taken though its row counts it out;
  marking it needs a
  field in the schema.
- Top cards, code outside every def, are as before.
