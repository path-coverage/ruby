require_relative 'card_context'
require_relative 'card_scopes'
require_relative 'card_tree'
require_relative 'card_ways'
require_relative 'method_statements'
require_relative 'source_lines'

module PathCoverage
  # What is measured within each method of a covered file.
  module WithinMethods
    # Where each statement of the covered file at path, parsed
    # as Manifest.parse gives it, that is no decision is reached,
    # as MethodStatements.reaches gives them.
    def self.reaches(path, parsed, config)
      source, decisions = parsed.values_at(:source, :decisions)
      relative = config.relative(path)
      MethodStatements.reaches(source, relative, decisions)
    end

    # Example: { "k.rb:0:0" => [1, 2], "k.rb:1:0" => [2, 4] }.
    # Each def's card total, [taken, size], in every file in
    # files, { full path => {source:, decisions:} }, from paths, as
    # Result#paths gives them, and reached, as Recorder#reached
    # does; and each file's top level's, its decisions on no card,
    # named for line 0, which no def is on.
    def self.cards(files, config, paths, reached)
      files.map do |full_path, parsed|
        path = config.relative(full_path)
        source, decisions = parsed.values_at(:source, :decisions)
        args = [source, path, paths]
        top = MethodStatements.top_level(*args, decisions)
        CardContext.totals(*args, reached, decisions)
                   .merge("#{path}:0:0" => top)
      end.reduce({}, :merge)
    end

    # Example: { "k.rb:1:0" => { "name" => "ship", "first" => 1,
    # "last" => 3, "rows" => [{ "at" => "2:04", ... }] } }.
    # Each card in every file in files, a def's and a top card's,
    # as its page draws it, for the JSON report, so a reader
    # finds a card's gap without the page; result a Result,
    # reached as cards takes it.
    def self.listed(files, config, result, reached)
      files.map do |full_path, parsed|
        path = config.relative(full_path)
        recorded = [result.operands, result.paths]
        listed_in(path, parsed, result.paths, reached)
          .merge(listed_tops(path, parsed, recorded))
      end.reduce({}, :merge)
    end

    # Example: { "k.rb" => { "1:0" => { "2:2" => { "parent" =>
    # nil, "in" => nil, "on" => nil } } } }.
    # How the rows of each card nest, in every file in files: by
    # the file's path, then its card's line:column, a def's card
    # and each top card, as listed names them, then each row's,
    # as CardTree places them; result a Result.
    def self.tree(files, config, result)
      files.to_h do |full_path, parsed|
        path = config.relative(full_path)
        [path, tree_in(path, parsed, result)]
      end
    end

    # How the rows of each card of the file at path nest, parsed
    # as Manifest.parse gives it, as tree gives them.
    def self.tree_in(path, parsed, result)
      source, decisions = parsed.values_at(:source, :decisions)
      cards = CardTree.of(source, path, decisions).to_a +
              tree_tops(path, parsed, result)
      cards.to_h do |decision, rows|
        [decision.split(':').last(2) * ':', rows]
      end
    end

    # [[card decision, its rows' places]] for each top card of the
    # file at path, as listed_tops names them.
    def self.tree_tops(path, parsed, result)
      source, decisions = parsed.values_at(:source, :decisions)
      lines = SourceLines.of(source, decisions, result.operands)
      spans(path, parsed, lines).map do |span, rows|
        nested = CardTree.nested(source, decisions, rows)
        ["#{path}:#{span.begin}:0", nested]
      end
    end

    # The top cards of the file at path, as its page draws them:
    # each under the decision of its first line's start, named for
    # its scope, as listed gives them; operands and decision_paths
    # as Result gives them.
    def self.listed_tops(path, parsed, (operands, decision_paths))
      source, decisions = parsed.values_at(:source, :decisions)
      lines = SourceLines.of(source, decisions, operands)
      scopes = CardScopes.of(source)
      spans(path, parsed, lines).to_h do |span, rows|
        decision = "#{path}:#{span.begin}:0"
        taken = rows.zip(MethodStatements.taken(rows, decision_paths))
        ways = CardWays.card(source, decisions, rows)
        named = [scopes[span.begin], span.end, ways, nil]
        [decision, card(decision, named, taken)]
      end
    end

    # { span => its top-level rows } of the file at path, each
    # row under the span its line is in, lines as SourceLines.of
    # gives them.
    def self.spans(path, parsed, lines)
      source, decisions = parsed.values_at(:source, :decisions)
      rows = MethodStatements.top_rows(source, path, decisions)
      rows.group_by { lines[_1.line - 1][:span] }
    end

    # The cards of the file at path, parsed as Manifest.parse
    # gives it, as listed gives them.
    def self.listed_in(path, parsed, paths, reached)
      source, decisions = parsed.values_at(:source, :decisions)
      names = MethodStatements.names(source, path, decisions)
      lasts = MethodStatements.lasts(source, path, decisions)
      MethodStatements.of(source, path, decisions).to_h do |key, rows|
        ways = CardWays.card(source, decisions, rows)
        named = [names[key], lasts[key], ways, reached&.fetch(key, 0)]
        shown = CardContext.rows(source, decisions, rows, paths,
                                 reached)
        [key, card(key, named, shown)]
      end
    end

    # The card of the def at decision, named name, ending on line
    # last, with ways through it, as ways folds them, and calls,
    # how many times it was called, nil for a top card, which is no
    # method's, or when not known: its first line, from decision, and
    # a row for each [statement, taken] of rows.
    def self.card(decision, (name, last, ways, calls), rows)
      first = Integer(decision.split(':')[-2])
      listed = rows.map { |statement, count| row(statement, count) }
      { 'name' => name, 'first' => first, 'last' => last,
        'ways' => ways, 'calls' => calls, 'rows' => listed }
    end

    # A card's row: statement's line:column, as its page labels
    # it, its top, its paths, count, how many were taken, and
    # its decision, nil for a statement that is no decision.
    def self.row(statement, count)
      { 'at' => MethodStatements.at(statement),
        'top' => statement.top, 'paths' => statement.paths,
        'taken' => count, 'decision' => statement.decision }
    end
  end
end
