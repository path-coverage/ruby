# Schemas as test generators

The schemas (path-coverage/schemas) say what a valid
`path_coverage.json` and `path_coverage.source.json` look like. That
is enough to generate them, so the schemas can drive property tests of
everything that reads reports, not just check what the tools write.

## What could use generated reports

- **html-reporter.** Generate valid report pairs and check that
  report.js never crashes: it either writes pages whose data is valid
  against its own schema.json, or refuses with a clear message.
- **Merging.** Generate several reports with equal fingerprints
  (`kinds`, `ignored`, `treats`, `measured_by`) and check properties
  of `Render.from_json(config, paths)`: merged counts are the sums;
  merging is order-free (commutative, associative); merging one report
  with an empty one changes nothing.
- **Refusing.** Generate reports that differ from the reader's
  fingerprint in exactly one key and check each is refused, with the
  message that names that key ("measured other kinds", "was measured
  by other tools").
- **Round trips.** Read a generated report and write it back
  (JsonReader, then JsonWriter): the same JSON.
- **Invalid input.** Mutate a valid generated report so it breaks one
  schema rule (a missing required key, a wrong type, an unknown key)
  and check every reader refuses it rather than mis-reading it.

## The catch: the schemas say too little

A schema checks each part's shape, not how the parts fit together.
A report valid by the schema can still be incoherent:

- a decision named in `paths` that `decisions` does not have;
- a leaf span outside its file's lines in the source report;
- a card row naming a decision the report does not have;
- `totals` that do not add up to the paths' counts;
- a `path` with more outcomes than its decision has leaves.

Randomly generated reports would be mostly incoherent, so a reader
refusing them says little. Three ways round it:

1. **State the cross-references in the schemas** where JSON Schema can
   (it cannot express most of them), and generate from those.
2. **Generate from the schema, then repair**: a small fix-up step
   makes the parts agree (drop paths with no decision, recompute
   totals). Coherent reports for the reader's main path, and the raw
   incoherent ones for the "refuse cleanly" property.
3. **Generate from code instead**: run the gem on code from the
   generated-method grammar (test/property/method_grammar.rb) and use
   the reports it writes. Coherent by construction, but only as varied
   as the grammar.

Probably 2 and 3 together: 3 for realistic reports, 2 for shapes the
gem never writes but a hand-edited or future report might.

## Tools (not yet checked)

Libraries exist that generate data from a JSON Schema, eg
hypothesis-jsonschema for Python (Hypothesis strategies from a schema)
and json-schema-faker for JavaScript. Which support draft 2020-12
features the schemas use (`prefixItems`, `$defs`, `propertyNames`) is
not yet checked.

## Open questions

- Which repo holds these tests: each reader's own (html-reporter for
  the pages, ruby and python for merging), with the schemas image
  supplying the schemas as it does for validation today?
- How to seed generation so a failing report can be replayed, as the
  generated-method tests do with SEEDS.
- Whether to add a "coherent" schema of the cross-references, as a
  second check the readers run after the shape schema.
