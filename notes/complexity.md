# A complexity metric per method

## What we have

A card already shows `*N`: its rows' paths multiplied
(`MethodStatements.complexity`). That is right for statements in
sequence, but wrong for nesting. Here the card's rows are the `if`
(2 paths) and the `&&` in its `then` (3 paths), so `*N` is 6:

```ruby
def fee(member, paid, big)
  if member
    paid && big ? 5 : 10
  else
    0
  end
end
```

But there are only 4 ways through it: `else`, or `then` with each of
the `&&`'s 3 paths. Multiplying everything overstates nested code and
would punish a guard clause as much as two independent decisions.

## Proposal: count the ways through the method

The number of distinct ways one call can go through the method,
built from the structure:

- statements one after another: multiply (each way through the first
  goes on to each way through the next);
- an `if`, `case` or ternary: add up its arms' ways, each times the
  predicate paths that lead to that arm;
- a decision with no arms (`&&`, `&.`, `any?`): its own paths, as the
  card already counts them;
- a statement that is no decision: 1.

This is the known NPATH metric (Nejmeh, 1988), so we can cite it, and
our decisions give it better inputs than usual: `&.`, block methods and
`||=` count as the paths they really have. In the example: else 1,
plus then 3 = 4.

It is easy to explain: "the number of different ways a single call
can go through this method". More paths always means a higher number,
which is the property that matters.

## How to present and gate it

- Show it on the card in place of `*N`, and per method in the JSON
  (`cards[...].ways`), so an AI can read it.
- It grows fast (10 independent ifs give 1024), so offer a gate:
  `max_ways 200` fails the run naming each method over it, as
  `coverage: DENIED` does. 200 is PMD's NPATH default.
- Keep `size` (the sum, paths a test suite must take one at a time)
  beside it: size is test effort, ways is complexity.

## Open question

Loops and block bodies: count a block body once, as its decision's paths
already cover 0, 1 and many items. That keeps the number finite and
honest without inventing loop iteration counts.
