require 'prism'
require_relative 'card_tree'
require_relative 'card_ways'
require_relative 'method_statements'
require_relative 'source_lines'

module PathCoverage
  # What is measured within each method of a covered file.
  module WithinMethods
    # Where each statement of the covered file at path, parsed
    # as Manifest.parse gives it, that is no site is reached, as
    # MethodStatements.reaches gives them.
    def self.reaches(path, parsed, config)
      source, sites = parsed.values_at(:source, :sites)
      MethodStatements.reaches(source, config.relative(path), sites)
    end

    # Example: { "k.rb:0:0" => [1, 2], "k.rb:1:0" => [2, 4] }.
    # Each def's card total, [taken, size], in every file in
    # files, { full path => {source:, sites:} }, from paths, as
    # Result#paths gives them, and reached, as Recorder#reached
    # does; and each file's top level's, its sites on no card,
    # named for line 0, which no def is on.
    def self.cards(files, config, paths, reached)
      files.map do |full_path, parsed|
        path = config.relative(full_path)
        source, sites = parsed.values_at(:source, :sites)
        top = MethodStatements.top_level(source, path, paths, sites)
        MethodStatements.totals(source, path, paths, reached, sites)
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
      source, sites = parsed.values_at(:source, :sites)
      cards = CardTree.of(source, path, sites).to_a +
              tree_tops(path, parsed, result)
      cards.to_h do |site, rows|
        [site.split(':').last(2) * ':', rows]
      end
    end

    # [[card site, its rows' places]] for each top card of the
    # file at path, as listed_tops names them.
    def self.tree_tops(path, parsed, result)
      source, sites = parsed.values_at(:source, :sites)
      lines = SourceLines.of(source, sites, result.operands)
      spans(path, parsed, lines).map do |span, rows|
        nested = CardTree.nested(source, sites, rows)
        ["#{path}:#{span.begin}:0", nested]
      end
    end

    # The top cards of the file at path, as its page draws them:
    # each under the site of its first line's start, named for
    # its scope, as listed gives them; operands and site_paths as
    # Result gives them.
    def self.listed_tops(path, parsed, (operands, site_paths))
      source, sites = parsed.values_at(:source, :sites)
      lines = SourceLines.of(source, sites, operands)
      scopes = scopes(source)
      spans(path, parsed, lines).to_h do |span, rows|
        site = "#{path}:#{span.begin}:0"
        taken = rows.zip(MethodStatements.taken(rows, site_paths))
        ways = CardWays.card(source, sites, rows)
        named = [scopes[span.begin], span.end, ways, nil]
        [site, card(site, named, taken)]
      end
    end

    # { span => its top-level rows } of the file at path, each
    # row under the span its line is in, lines as SourceLines.of
    # gives them.
    def self.spans(path, parsed, lines)
      source, sites = parsed.values_at(:source, :sites)
      rows = MethodStatements.top_rows(source, path, sites)
      rows.group_by { lines[_1.line - 1][:span] }
    end

    # A lambda giving the scope of a line of source, as scope
    # gives it, its modules and classes found once.
    def self.scopes(source)
      holders = holders_in(Prism.parse(source).value)
      ->(line) { scope(holders, line) }
    end

    # Example: line 2, inside module Shop on lines 1 to 9, gives
    # Shop.
    # The name of the innermost of holders, modules and classes,
    # whose lines hold line, a top card's scope, as a def is a
    # method card's; file for a line in none.
    def self.scope(holders, line)
      holding = holders.select do |node|
        location = node.location
        (location.start_line..location.end_line).cover?(line)
      end
      holding.empty? ? 'file' : holding.last.name.to_s
    end

    # The kinds of node that are a top card's scope.
    HOLDERS = [Prism::ModuleNode, Prism::ClassNode].freeze

    # Every module and class node in the tree at node, each
    # before those nested in it.
    def self.holders_in(node)
      own = HOLDERS.include?(node.class) ? [node] : []
      own + node.compact_child_nodes.flat_map { holders_in(_1) }
    end

    # The cards of the file at path, parsed as Manifest.parse
    # gives it, as listed gives them.
    def self.listed_in(path, parsed, paths, reached)
      source, sites = parsed.values_at(:source, :sites)
      names = MethodStatements.names(source, path, sites)
      lasts = MethodStatements.lasts(source, path, sites)
      MethodStatements.of(source, path, sites).to_h do |site, rows|
        taken = MethodStatements.taken(rows, paths, reached)
        ways = CardWays.card(source, sites, rows)
        calls = reached.fetch(site, 0)
        named = [names[site], lasts[site], ways, calls]
        [site, card(site, named, rows.zip(taken))]
      end
    end

    # The card of the def at site, named name, ending on line
    # last, with ways through it, as ways folds them, and calls,
    # how many times it was called, nil for a top card, which is no
    # method's, or when not known: its first line, from site, and
    # a row for each [statement, taken] of rows.
    def self.card(site, (name, last, ways, calls), rows)
      first = Integer(site.split(':')[-2])
      listed = rows.map { |statement, count| row(statement, count) }
      { 'name' => name, 'first' => first, 'last' => last,
        'ways' => ways, 'calls' => calls, 'rows' => listed }
    end

    # A card's row: statement's line:column, as its page labels
    # it, its top, its paths, count, how many were taken, and
    # its site, nil for a statement that is no site.
    def self.row(statement, count)
      { 'at' => MethodStatements.at(statement),
        'top' => statement.top, 'paths' => statement.paths,
        'taken' => count, 'site' => statement.site }
    end
  end
end
