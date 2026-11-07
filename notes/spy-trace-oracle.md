# Spy traces as a property-test oracle

How the generated property tests can check that path coverage's
rewrite runs exactly the same path as the plain code, not just that
it gives the same result. The same idea applies to the Python port.

## Where it starts

`test/property/load_test.rb` (Pq3L10) generates small methods from
`test/property/method_grammar.rb`, each leaf a fresh boolean
parameter. It runs each method on every combination of its
parameters twice: loaded plainly (`module_eval`, call it C) and loaded
under path coverage (`t.load`, which runs the rewrite, R). It asserts
the two give the same value, or both raise.

That misses a rewrite that evaluates a leaf twice, skips one, runs
them in another order, or skips a statement whose effect does not
reach the method's value.

## The idea

The trace comes from the test's inputs, not from any instrumentation.
The generated code calls its parameters, and the test passes spies:

```ruby
# generated
def self.run(p0, p1, s)
  t = 0
  s.(0); p0.() or return t
  s.(1); t += 1 if p1.()
  t
end

# oracle, for one combination of inputs
trace = []
leaves = values.each_with_index.map do |value, i|
  -> { trace << [:leaf, i]; value }
end
step = ->(n) { trace << [:statement, n] }
[run(*leaves, step), trace]   # or [:raised, trace] for a Stop
```

C and R both run the same calls, so each logs to the spies exactly as
the program behaves. Comparing `[value, trace]` from C and R checks:

- each leaf evaluated the same number of times, in the same order;
- each statement run or skipped alike, because every statement logs
  before it runs (`s.(n);`).

For the generated code, the interleaved trace of leaves and
statements is the path taken. So equal traces mean equal paths, for
every construct the grammar generates and no further.

## Where a spy can go

A spy is a call, so it fits only where an expression is allowed, and
only where replacing the leaf does not change what the gem decides
about it.

```
position                        spy?   how
&&/||/and/or operand, if/while  yes    p0.()
?: arms, block bodies (any?)    yes    p0.(), p0.(item) also logs early stop
&. receiver                     yes    p0.() returns nil or an object
x ||= v target                  yes    box.v ||= ..., box a spy (attr calls)
local/ivar leaf                 no     must stay: the gem treats them apart
literal leaf ("x", nil)         no     must stay: the gem marks them fixed
case/in patterns, Python        no     patterns are not expressions; log
  match patterns, mapping keys         the guard (if g.()) and the body
x or return t (right side)      no     (s.(); return t) changes the AST,
                                       so a return shows as later logs absent
statements                      yes    s.(n); before each, not inside exprs
```

Notes on the rows:

- **Locals, ivars and literals stay.** The gem handles a local
  variable leaf and a literal leaf (fixed outcomes) differently from
  a call, so a grammar of only callable leaves would stop testing
  those paths. The grammar mixes both kinds. Their reads have no side
  effects, so the leaves and statements around them still give the
  path.
- **Patterns are syntax.** A `case/in` pattern, or a Python `match`
  pattern or mapping-pattern key, cannot be a call (a pin,
  `^(p0.())`, changes the AST). Which case ran shows in its guard's
  spy and its body's statement log.
- **Arms that leave.** Wrapping `return t` as `(s.(n); return t)`
  makes the operand a begin node, so `Leaving` no longer sees it
  leave, and the test would stop testing what it means to. A return
  shows instead as the absence of every later log, and in the value.
- **Statement logs go between statements only**, never inside an
  expression, so they never change an expression's shape.

## A second oracle: the gem's own records

The same trace gives each decision's actual path for each call: the
outcome of each of its leaves, in order. Counting those over every
input combination gives the taken paths the gem must report.

So a second property compares the trace-derived counts with the
`taken` counts in `path_coverage.json`, decision by decision. The
first property checks that the rewrite does not disturb the program;
this one checks that the gem records what the program actually did.
Only leaves with spies can be checked this way; a local or literal
leaf's outcome is known from the inputs and the grammar instead.

## Open questions

- How to name the spies in a generated method so that a failure
  message reads as code (`p0`, `s`), not as indices.
- Whether statement logs should carry the line number, so a trace
  diff points at the source.
- How the Python port passes the statement spy (a parameter, or a
  module global the snippet reads).
- The cost: a trace per input combination is at most 256 calls a
  method; the budget is the property suite's few seconds.
