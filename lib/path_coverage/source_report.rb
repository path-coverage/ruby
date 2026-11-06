require_relative 'code_tokens'
require_relative 'fold_rows'
require_relative 'decision_locations'
require_relative 'decision_tree'
require_relative 'source_lines'
require_relative 'summary'

module PathCoverage
  # What a renderer needs of each covered file beyond the JSON
  # report's counts, worked out from its source, so it can draw
  # the file's page without parsing the source itself.
  module SourceReport
    # The version of the source report's shape.
    SCHEMA = 1

    # The source report of a run: config's ignored operators, the
    # covered files of each of config's groups, each top of the
    # rows of cards, { def decision => card }, coloured, and each of
    # files', { full path => {source:, decisions:} }, lines and
    # decisions, each decision's paths as decision_paths has
    # them, its fold headed by its row's top.
    def self.of(files, config, decision_paths, cards)
      rows = cards.values.flat_map { _1['rows'] }
      tops = rows.to_h { [_1['decision'], _1['top']] }
      shown = files.to_h do |full_path, parsed|
        [config.relative(full_path),
         file(parsed, decision_paths, tops)]
      end
      { schema: SCHEMA, ignored: config.ignored,
        groups: groups(config, shown.keys), labels: labels(rows),
        files: shown }
    end

    # { top => it coloured } of each distinct top of rows, a
    # decision's or a statement's, eg return.
    def self.labels(rows)
      rows.map { _1['top'] }.uniq.to_h do |top|
        [top, CodeTokens.label_code(top)]
      end
    end

    # { name => the paths its globs match } of each of config's
    # groups.
    def self.groups(config, paths)
      config.groups.transform_values do |globs|
        paths.select { Summary.matches?(_1, globs) }
      end
    end

    # One file's lines and decisions, parsed being its {source:,
    # decisions:}.
    def self.file(parsed, decision_paths, tops)
      source, decisions = parsed.values_at(:source, :decisions)
      shown = decisions.keys.to_h do |name|
        paths = decision_paths.fetch(name)
        [name,
         decision(source, decisions, name, paths, tops.fetch(name))]
      end
      { lines: lines(source), decisions: shown }
    end

    # Example: "ok?(1)\n" gives [{ text: 'ok?(1)', tokens:
    # [[4, 5, 'n']] }].
    # Each line of source: its text and its coloured tokens.
    def self.lines(source)
      tokens = CodeTokens.of(source)
      source.lines.each_with_index.map do |text, index|
        { text: text.chomp, tokens: tokens.fetch(index + 1, []) }
      end
    end

    # Example: ok?(id) && new?(id) on line 2 gives span [2, 2].
    # The decision named name, of decisions, { name => Condition }, in
    # source: the [first, last] lines it spans, and its fold's
    # rows, headed by top, its row's top, a column for each of
    # paths, [{path:, count:}], in their order, with no counts.
    def self.decision(source, decisions, name, paths, top)
      condition = decisions.fetch(name)
      last = SourceLines.end_line(source, condition.leaves.last)
      span = [SourceLines.line_of(name), last]
      { span:, fold: fold(source, condition, paths, top) }
    end

    # The rows of condition's fold, headed by top, its decision row
    # with no counts.
    def self.fold(source, condition, paths, top)
      outcomes = paths.map { _1[:path] }
      tree = DecisionTree.built(source, condition, outcomes)
      located = DecisionLocations.located(source, condition, tree)
      else_at = DecisionLocations.else_at(source, condition)
      own, *rest = FoldRows.rows(located.merge(else_at:, label: top))
      [own.except(:counts), *rest]
    end
  end
end
