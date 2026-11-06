# Unfolding: one row per element that can change the path

## The idea

Today a condition nested inside another's expression is folded into
one decision: its leaves join the outer decision's, and its paths multiply
into the outer decision's paths. The card shows one row, with one wide
grid.

Statements are not treated that way: `x = 1; y = 2` is two rows, and
an `if` inside an `if` is two rows, the inner one placed in the
outer's arm by the JSON's `tree`.

Unfolding treats expressions the same way. Every element that can
change the path is a decision, and a row, of its own. The tree says when
each one runs (`parent`, `in`, `on`). One new fact is needed, `gives`:
what a child's outcome makes of the parent's leaf that holds it.

The numbers below are from Manifest and DecisionPaths at 841c2a5.

## Sample 1: an && holding a ?:

```ruby
def f(a, b)
  a && (b ? 1 : 2)
end
```

Folded today: one decision, `2:2 &&`, leaves `a`, `b`, `b ? 1 : 2` (the
?:'s value, as the &&'s last operand):

```
0  [true,  true,  true ]
1  [true,  true,  false]   impossible: b true gives 1, truthy
2  [true,  false, true ]
3  [true,  false, false]   impossible: b false gives 2, truthy
4  [false, nil,   nil  ]
```

5 paths, 2 of them impossible. The folding does not know that 1 and
2 are truthy, so it cannot rule them out.

Unfolded: two decisions.

```
2:2  &&  leaves a, (b ? 1 : 2)      paths [T,T] [T,F] [F]
2:8  ?:  leaf b                     paths [T] [F]
         parent 2:2, in nil, on [0, 1]   (where its leaf runs)
         gives  then -> true, else -> true
```

With `gives`, the && path [T,F] needs a ?: path giving false, and
none does: it is impossible, and shown so. Counting the ways through:
[T,T] runs the ?:'s 2 paths, [T,F] none, [F] 1: 3 in all, every one
possible.

Without `gives` (an arm whose truthiness is not known, eg a call),
each child path gives both, and the count is 2 + 2 + 1 = 5, as the
folded decision has now. So `gives` only ever removes impossible paths.

## Sample 2: an && holding select { }.any?

```ruby
def f(a, xs)
  a && xs.select { |x| x.odd? }.any?
end
```

Folded today: one decision, `2:2 &&`, leaves `a`, `xs` (select's item
count), `x.odd?` (its answers), and `xs.select { ... }.any?`: 13
paths, `a` false once, then 6 select paths times any? true or false.
Half of those 12 are impossible: any? is true exactly when select
kept an item, ie its answers were all true or both.

Unfolded:

```
2:2   &&      leaves a, (xs.select {...}.any?)  paths [T,T] [T,F] [F]
2:10  select  leaves xs, x.odd?                 6 paths
              parent 2:2, on [0, 1]
              gives  0 items -> false, all false -> false,
                     all true -> true, both -> true
2:23  value   x.odd?, parent 2:10, on its 5 paths with an item
```

Ways through: [T,T] with select's 3 paths that keep an item, [T,F]
with its 3 that keep none, [F] alone: 7, every one possible, where
the folded decision lists 13.

The fact `gives` needs is already known: the Block kind's value
function says what select's result holds on each path (VALUED).

## Sample 3: a ?: in a ?:'s arm

```ruby
def f(a, b)
  a ? (b ? 1 : 2) : 3
end
```

Folded today: one decision, `2:2 ?:`, leaves `a`, `b`: [T,T] [T,F] [F,nil].
3 paths, all possible: nothing is lost by folding here.

Unfolded:

```
2:2  ?:  leaf a   paths [T] [F]
2:7  ?:  leaf b   paths [T] [F]
         parent 2:2, in then, on [0]
         gives  nothing: an arm's value is no leaf of the parent
```

Ways through: then runs the inner 2, else 1: 3, the same. The card
shows two rows of 2 paths, not one of 3.

## What it simplifies

- A card row per element, each grid as narrow as its own leaves.
- The decision kinds stop composing: Contains, and the folding in
  ManifestFolding, go; a decision's paths are its own leaves' only.
- The tree carries all nesting, statements and expressions alike,
  so the complexity fold (notes/complexity.md) has one shape to fold.
- The impossible combined paths of a fold (an open item) become
  `gives` facts, ruled out where known.

## What it costs

- The recorder records each decision on its own, so the rewriter's
  nested inserts change: each nested decision gets its own enter and
  leave, inside its parent's leaf.
- Per-decision counts no longer hold joint outcomes. They come back,
  for the whole method, from recording each call's whole path (see
  Decided): one array write per evaluation, one hash increment per
  call or loop pass.
- Every kind needs a `gives`: what its value is on each of its paths,
  or nil for not known. Choice needs the truthiness of literal arms,
  which the manifest does not note today (`fixed` is empty for 1).

## Decided

- A child names the leaf of its parent that it gives, as a parent
  can have two leaves each holding a child:

  ```ruby
  def f(a, b)
    (a ? 1 : nil) && (b ? 2 : nil)
  end
  ```

  ```
  2:2   &&  leaves 0: (a ? 1 : nil)   1: (b ? 2 : nil)
  2:3   ?:  parent 2:2, leaf 0, gives then -> true, else -> false
  2:18  ?:  parent 2:2, leaf 1, gives then -> true, else -> false
  ```

  The tree already finds that leaf by position; it is written down.

- Each card has two tabs. One is the rows, as now. The other is the
  card's complexity, eg 37, the ways through the method folded over
  the tree. Impossible paths, those `gives` rules out, are not
  counted or shown.

- The complexity tab does not try to draw how decisions connect, or how
  that multiplies the count. The code pane already shows that
  structure. The tab is one column per way, each covered or not,
  with its count on hover:

  ```
  complexity 4     [1] [2] [3] [4]
                    *   0   *   0
  ```

- Choosing a column paints that one way onto the code pane: each
  leaf's outcome on it, the code it runs lit, the code it skips
  dimmed, and where it returns or raises:

  ```
  way 3:
    if member && paid     member T  paid F
      total -= 5          dimmed: not run on this way
    end
    return 0 if big       big T: the way ends here
    total                 dimmed
  ```

  So a gap reads as code: the dimmed lines and red leaves say what a
  test must do to take that way.

- Per-decision counts cannot say which whole paths were taken:

  ```ruby
  def f(a, b)
    x = a ? 1 : 2      # 2 paths
    y = b ? 3 : 4      # 2 paths    complexity 4
  end
  f(true, true); f(false, false)
  ```

  ```
  per-decision counts:  a: T,F both taken   b: T,F both taken
  whole paths:      TT taken  FF taken  TF never  FT never
  ```

  So the recorder keeps, per method call, a small array with a slot
  per decision of the method. Each evaluation writes its decision's path to
  its slot. When the call returns, the array is the call's whole
  path, and is counted.

- A loop body is a unit of its own, run once per pass, as the
  complexity fold counts a body once. Each pass fills the body's own
  array, counted at the end of the pass. So 100,000 passes of one ?:
  leave at most 2 entries, never 100,000: memory is bounded by the
  number of possible paths, not by how often code runs.

  ```
  def f(xs)                 method unit:  decisions outside the loop
    xs.each do |x|          body unit:    one tuple per pass
      p(x ? 1 : 2)
    end
  end
  ```

- Whole paths are counted, not just noted, as a hash of tuple to
  count, so the whole-path view's 0 and * cells keep their hover tip
  of how many times, as the per-decision cells have now:

  ```
  body counts   = { [T] => 61_402, [F] => 38_598 }
  method counts = { [T, T] => 3, [F, F] => 1 }   # TF, FT: 0
  ```

- A card keeps only rows that shape paths: decisions, and return and
  raise rows, which end a path. A row that is no decision and has one
  path, eg total -= 2, runs exactly where its parent's arm does,
  so it is dropped from the card and from the JSON, and its reach
  call with it.

- So that a method with no decisions, never called, cannot read as
  covered, each card has a call-count: a counter at its def's
  entry, in the JSON card and the card's title, 0 shown as a gap.

- A decision whose arm returns or raises, eg return total if
  order[:pickup], gets a row in its fold, return or raise, marked
  on each path that leaves the method (drawn here as <-), blank on
  the others:

  ```
  v 50:17  if            *    *
      |- order[:pickup]  F    T
      `- return               <-
  ```

## Open questions

- Order of work, so far: ?: in a ?: arm, a valued block call
  wholly a leaf or arm, an && or || predicate. Next: call-count,
  then dropping one-path rows, then the return row.
