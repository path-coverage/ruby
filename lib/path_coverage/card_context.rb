require_relative 'card_tree'
require_relative 'card_ways'
require_relative 'method_statements'
require_relative 'way_algebras'

module PathCoverage
  # The paths of each def's card rows that its method can take:
  # those on some way through the card, as CardWays folds it,
  # and any taken that it rules out, which are counted, never
  # dropped, and reported. Paths combined count these, where paths
  # alone count each decision's paths on its own.
  # paths is as Result#paths gives it, and reached as
  # Recorder#reached does, nil when not known.
  module CardContext
    # Example: { "k.rb:1:0" => [2, 3] } for ship, its first row's
    # 2 paths both taken, its second's 1 path, of 2, that its
    # method can take, not taken.
    # Each def's card total in source, [taken, size], its rows'
    # taken as MethodStatements.taken gives them, a row not known
    # counting as not taken, and its size their paths as rows
    # gives them.
    def self.totals(source, path, paths, reached, decisions)
      cards = MethodStatements.of(source, path, decisions)
      cards.transform_values do |rows|
        shown = rows(source, decisions, rows, paths, reached)
        seen = shown.filter_map(&:last).sum
        [seen, MethodStatements.size(shown.map { _1.first.paths })]
      end
    end

    # [row, taken] for each of rows, a card's in source: row with
    # as its paths how many of them its method can take or took,
    # as of gives them, and taken as MethodStatements.taken gives
    # it.
    def self.rows(source, decisions, rows, paths, reached)
      context = of(source, decisions, rows, paths, reached)
      shown = rows.zip(context).map do |row, (can, took)|
        row.with(paths: (can | took).size)
      end
      shown.zip(MethodStatements.taken(rows, paths, reached))
    end

    # Example: [[[1], [1]], [[0, 1], [0]]] for return 0 if a, then
    # a ?: of b, called once with a false and b true.
    # [the indices of its paths its method can take, those taken]
    # for each of rows, a card's in source: those on some way
    # through the card, as WayAlgebras::Labelled folds them; and
    # those taken, a return's or a raise's one path index 0.
    def self.of(source, decisions, rows, paths, reached)
      labelled = WayAlgebras::Labelled
      labels = CardWays.card(source, decisions, rows, labelled)
      by_key = labels.group_by(&:first)
      rows.map do |row|
        can = by_key.fetch(CardTree.key_of(row), []).map(&:last)
        [can, taken_paths(row, paths, reached)]
      end
    end

    # The indices of the paths of row taken: of its decision's
    # paths, those with a count in paths; for a return or a raise,
    # its one path when reached counts it, none when not, or when
    # reached is nil, not known.
    def self.taken_paths(row, paths, reached)
      decision = row.decision
      return reached.to_h.key?(row.name) ? [0] : [] if decision.nil?

      counts = paths.fetch(decision).map { _1[:count] }
      counts.each_with_index.map { |n, at| at if n.positive? }.compact
    end

    # Example: [["k.rb:5:11", [true]]], a ?:'s true path taken past
    # return 0 if a, a's local having been set by other code.
    # [name, path] for each path taken in files, { full path =>
    # {source:, decisions:} }, under config, that its method rules
    # out, as of finds them, as ruled_in gives them.
    def self.ruled_out(files, config, paths, reached)
      files.flat_map do |full_path, parsed|
        source, decisions = parsed.values_at(:source, :decisions)
        path = config.relative(full_path)
        cards = MethodStatements.of(source, path, decisions)
        cards.values.flat_map do |rows|
          ruled_in(source, decisions, rows, paths, reached)
        end
      end
    end

    # [name, path] for each path of rows, a card's in source, taken
    # though its method rules it out: a decision's name and the
    # path, as paths has it; a return's or a raise's and nil.
    def self.ruled_in(source, decisions, rows, paths, reached)
      context = of(source, decisions, rows, paths, reached)
      rows.zip(context).flat_map do |row, (can, took)|
        (took - can).map { [row.name, path_at(row, _1, paths)] }
      end
    end

    # The path at index among those of row's decision, as paths
    # has it; nil for a return or a raise, which has no decision.
    def self.path_at(row, index, paths)
      decision = row.decision
      decision ? paths.fetch(decision)[index][:path] : nil
    end
  end
end
