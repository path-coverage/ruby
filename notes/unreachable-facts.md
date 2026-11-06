# Facts that make a path unreachable

## The problem

A path is listed as a gap whenever its form allows it. Some cannot
happen, and only the developer knows why:

```ruby
user&.name&.size        # name is never nil for a saved user
return if ids.empty?
ids.any? { |id| id.odd? }   # the "0 items" path cannot happen here
```

Today `treat 'name', as: :present` (optionally `in:` a glob) covers
the first, but by method name, everywhere it matches.

## The rule every strategy must keep

A fact is a claim, so it is checked, never trusted. A path a fact
rules out is not counted as possible; if a run takes it anyway, the
run reports it (as `outside` does today). So a wrong fact shows up as
a failure, never as a hidden gap. Fail toward non-compliance.

## Strategies

1. Config by name (exists). `treat 'name', as: :present, in: 'app/**'`.
   Good for facts about a library method used everywhere. Coarse: it
   cannot say "here, but not there".

2. A comment on the decision's line. Prism already gives us comments.

   ```ruby
   ids.any? { |id| id.odd? }   # paths: ids nonempty
   user&.name&.size            # paths: name present
   ```

   The fact sits beside the code it is about, moves with it, and is
   reviewed with it. Same vocabulary as `treat` (present, nonempty,
   later truthy). Unknown words in a `# paths:` comment are an error,
   so a typo never silently does nothing.

3. Config by decision name, eg `fact 'kata.rb:3:23', ...`. Breaks as soon
   as a line moves. Not recommended.

4. Derived from the code itself, no annotation:
   - a guard earlier in the method (`return if ids.empty?`) makes a
     later "0 items" path impossible;
   - the same leaf text twice in one decision (`a && b || a && c`) must
     have the same outcome on one evaluation, if it has no side
     effects;
   - RBS or Sorbet signatures saying a method never returns nil.
   Most precise for the user, most work for us, and each inference
   is a new way to be wrong, so each still needs the runtime check.

## Recommendation

Do 2 next: the `# paths:` comment, scoped to its decision, checked at
runtime, reusing the existing treatments. Keep 1 for library-wide
facts. Treat 4 as later work, one inference at a time, starting with
guard clauses, since "0 items" is the commonest impossible path.
The report should show ruled-out paths separately (eg "3 paths ruled
out by facts"), so a reader can see how much was assumed.
