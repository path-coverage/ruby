# Exception paths, in levels

Which paths an exception adds to a method, and how far to go in
counting them. The same idea applies to the Python port.

## Where it starts

`Leaving` (lib/path_coverage/leaving.rb) decides, statically, whether
a statement leaves the method: a `return`, or a call with no receiver
of `raise`, `fail` or `throw`. It sees only what is written in the
method itself:

- A direct `exit`, `exit!` or `abort` is not counted, nor is
  `Kernel.raise E` (a receiver). That is a gap in `Leaving.CALLS`,
  left until a test drives it.
- A call to a helper that raises or exits cannot be seen statically
  at all. The card's leaves rows and ways assume every call returns.
  The taken counts stay right, as they come from what ran.

Yet a raise does make paths of its own. Not rescued, it leaves the
method, as a return does. Rescued, it still matters where it came
from:

```ruby
def ship(order)
  begin
    a(order)
    b(order)
    c(order)
  rescue Timeout::Error
    retry_later(order)
  end
end
```

Each of `a`, `b` and `c` can raise, and each is a different way
through `ship`.

And not only calls: any statement can be interrupted by an exception
it did not cause, eg NoMemoryError, Interrupt from a signal, or
Thread#raise from another thread (MemoryError and KeyboardInterrupt in
Python). So in the strict sense these paths are possible everywhere.

## Levels

Each level adds paths to the one below it. And each level has both of
today's views: `alone`, each decision's paths on their own, and
`combined`, the ways through a method as a whole. So the totals are a
grid, not a list:

```
level        possible paths add                      taken by a test that...
decisions    decisions (today)                       chooses inputs
rescues      each rescue/except clause               makes the stated error happen
calls        each call in a method: returned/raised  stubs a callee to raise
async        each statement boundary: interrupted    injects faults (Thread#raise, signals)

             alone                     combined
decisions    Paths alone (today)       Paths combined (today)
rescues      + each rescue clause      + ways a rescue changes
calls        + each call's 2 outcomes  + ways each raise changes
async        + each boundary           + ways each interrupt changes
```

Every combined cell inherits today's open item: combined still counts
some paths that cannot happen. `gives` rules out those it knows
(notes/unfolding.md), but facts across decisions, eg a guard clause
making a later "0 items" path impossible, are not yet inferred
(notes/unreachable-facts.md, strategy 4). The higher levels multiply
the ways, so they multiply that error too; ruling out impossible
combined paths comes before them.

- **decisions**: what the gem counts now.
- **rescues**: only what the code itself states. Each `rescue E`
  clause (Python `except E`) is a path, taken when that clause runs.
  One that never ran is a gap: `rescue Timeout::Error never taken`.
  This is the level that respects the line between the method's logic
  and the runtime: asynchronous exceptions are the runtime's, not the
  method's.
- **calls**: each call statement is a decision of two outcomes,
  returned or raised. Inside a rescued body of n calls that gives n+1
  paths: `a` raised, `b` raised, `c` raised, none raised. Outside a
  rescue, a raise leaves the method, like a return. A test takes these
  by stubbing a callee to raise.
- **async**: each statement boundary can be interrupted. Taken only by
  fault injection. Useful for code that must be safe under interrupts,
  eg code holding a lock or a transaction.

For the `ship` example above (worked by hand, not run):

```
level       possible ways through ship
decisions   1   (no decision)
rescues     2   (body completes, or Timeout::Error rescued)
calls       4   (a, b or c raised and rescued, or none raised)
async       more: each of the 4 statements interrupted, by any error
```

## How it would show

- Each level gets an alone and a combined total of its own, eg
  `Paths rescues alone: 12 / 14` and `Paths rescues combined: 9 / 11`.
- A setting chooses the level the gate checks; the default stays
  `decisions`, so existing runs are unchanged.
- The card shows the rows of the chosen level, eg a `rescue` row with
  its taken count, and a call's `raised` cell.

## Measuring the taken side

- Ruby: TracePoint `:raise` gives each raise and where; a rescue
  clause's first statement shows that clause ran (a reach count, as
  today, or the rewrite's own call).
- Python: sys.monitoring RAISE, RERAISE and EXCEPTION_HANDLED events,
  with no rewrite, in step with the sys.monitoring rework.

## Open questions

- Which calls a `rescue E` covers is not known statically: whether `b`
  can raise E is the callee's business. At the calls level, count
  every call, or only those inside a rescue that could match?
- `ensure`/`finally`, `retry`, a re-raise in a rescue, `else`, and the
  rescue modifier (`x rescue y`): each needs its own rule.
- Size: the calls level adds a path per call statement almost
  everywhere; the async level adds one per statement boundary. Both
  need their own totals so they never swamp `decisions`.
- Whether `exit`/`abort` belong in `Leaving` (they leave the process,
  not just the method) or at the rescues level (SystemExit is an
  exception that `rescue Exception` catches).
