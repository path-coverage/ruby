require_relative 'card_fitting'
require_relative 'card_leaving'
require_relative 'card_rescues'
require_relative 'card_tree'
require_relative 'manifest'
require_relative 'method_statements'
require_relative 'decision_paths'
require_relative 'stable_leaves'
require_relative 'way_algebras'

module PathCoverage
  # The ways one call can go through each card, folded over its
  # tree, as CardTree places its rows. Each row gives a pair,
  # [ways that go on, ways that leave the method]: a return or a
  # raise leaves, and so does each path of a decision taking an
  # arm that returns or raises, eg return 0 if a. Rows one after
  # another multiply, but only the ways that go on reach the next
  # row; a decision adds up its paths, each with the rows it runs
  # on that path one after another; and a row that is the whole of
  # a leaf counts only those of its paths that give the leaf the
  # outcome the path has, so no impossible way is counted where
  # gives knows it. A block's body counts once, unless the block
  # forks, as CardForks folds it.
  # Each way also notes the outcome it gives each leaf that
  # StableLeaves finds, by its local's name, and two ways joined
  # one after the other that give one name both outcomes are no
  # way, as no call can take them.
  # The fold is in one of WayAlgebras: Counted counts the ways,
  # by default; Labelled gives the paths taken on any of them, and
  # Listed lists them.
  class CardWays
    include CardFitting
    include CardForks
    include CardLeaving
    include CardRescues

    # Example: { "k.rb:1:0" => 3 } for def f(a, b), return 0 if a,
    # then a ?: of b: 1 way leaves, 2 go on.
    # { def decision => its ways, in algebra } for each def in
    # source, its decisions those of no settings.
    def self.of(source, path, algebra = WayAlgebras::Counted)
      decisions = Manifest.decisions(source, path)
      cards = MethodStatements.of(source, path, decisions)
      cards.transform_values do |rows|
        card(source, decisions, rows, algebra)
      end
    end

    # The ways through a card of rows in source, in algebra,
    # decisions being { decision => Condition }, as
    # Manifest.decisions gives them; folding is [stable, forks]:
    # with stable false, those no call can take too, as no leaf is
    # then assigned; each loop of forks, as LoopForks gives them,
    # a fork, labelled [its key, 0] for 0 items, [its key, 1] for
    # 1+ items, then its body's rows, walked once.
    def self.card(source, decisions, rows,
                  algebra = WayAlgebras::Counted,
                  folding = [true, {}, {}])
      stable, forks, rescues = folding
      places = CardTree.nested(source, decisions, rows, forks)
      names = stable ? StableLeaves.of(source, decisions, rows) : {}
      new(source, rows, places, decisions,
          [algebra, names, rescues]).total
    end

    # The fold of rows, a card's in source, placed as places has
    # them, each decision row's Condition among decisions; folding
    # is [algebra, names, rescues]: its ways in algebra, each step
    # of it a tally of them, as WayAlgebras::Tallied has them,
    # assigning the leaves names has, as StableLeaves finds them,
    # its rescue forks as RescueForks gives a def's.
    def initialize(source, rows, places, decisions,
                   (algebra, names, rescues))
      @source = source
      @rows = rows.to_h { |row| [CardTree.key_of(row), row] }
      @places = places
      @decisions = decisions
      @ways = WayAlgebras::Tallied.new(algebra)
      @children = places.keys.group_by { places[_1]['parent'] }
      @names = names
      @rescues = rescues
    end

    # The ways through the card, in its algebra: its top rows'
    # triples, one after another, forked by its rescue, those that
    # go on and those that leave, whatever their assignments.
    def total
      tops = @children.fetch(nil, []).map { |key| pair_of(key) }
      all = rescued(sequence(tops))
      @ways.total(all.reduce { |sum, ways| @ways.plus(sum, ways) })
    end

    # The triple of rows one after another, from their triples:
    # the ways that go on through them all, and those that return,
    # and those that raise, at one of them, having gone on through
    # every one before it.
    def sequence(triples)
      start = [@ways.one, @ways.zero, @ways.zero]
      triples.reduce(start) do |(on, *out), (more, *leave)|
        through = leave.map { @ways.times(on, _1) }
        [@ways.times(on, more),
         *out.zip(through).map { @ways.plus(*_1) }]
      end
    end

    # The triple of the row keyed key: a decision's adds up its
    # paths' triples; any other row is a return or a raise, as no
    # other is a row, so leaves, by its word, at its one path.
    def pair_of(key)
      return fork_pair(key) unless @rows.key?(key)

      row = @rows[key]
      return left(row.top, @ways.unit([key, 0])) if row.decision.nil?

      triples = possible(row.decision).each_index.map do |path|
        pair_on(key, path)
      end
      added(triples)
    end

    # The triple of the decision row keyed key on its path at
    # index path: that path taken, then the rows it runs on that
    # path, one after another, each given that path's outcomes;
    # every way of it leaving, by the arm's word, when the path
    # takes an arm that leaves.
    def pair_on(key, path)
      outcomes = possible(@rows[key].decision)[path]
      triples = running(key, path).map do |child|
        child_pair(child, outcomes)
      end
      own = own(key, path, outcomes)
      ways = sequence(triples).map { @ways.times(own, _1) }
      leaving_by(ways, leaving(key)[path])
    end

    # The tally of the one way that takes the decision row keyed
    # key's path at index path, with outcomes, giving each name
    # the outcome of its leaves on it; no way when it gives a name
    # both outcomes, as eg a && b || a && c does with a true then
    # false.
    def own(key, path, outcomes)
      named = named(key, outcomes)
      assignment = named.to_h
      return @ways.zero if assignment.size < named.size

      @ways.unit([key, path], assignment)
    end

    # The distinct [name, outcome] of each leaf, of the decision of
    # the row keyed key, that outcomes reaches and that has a name.
    def named(key, outcomes)
      leaves = @decisions.fetch(@rows[key].decision).leaves
      leaves.zip(outcomes).filter_map do |range, outcome|
        next if outcome.nil? || !@names.key?(range)

        [@names[range], outcome]
      end.uniq
    end

    # The keys of the rows the decision row keyed key runs on its path
    # at index path, in the order they are written.
    def running(key, path)
      runs = @children.fetch(key, []).group_by do |child|
        @places[child]['on'].include?(path)
      end
      runs.fetch(true, [])
    end

    # The pair of the row keyed child, its parent's path having
    # outcomes: all of its own, for a row that gives nothing; else
    # those of only its paths that give its leaf the outcome that
    # path has, or that give what is not known.
    def child_pair(child, outcomes)
      return pair_of(child) if @places[child]['gives'].nil?

      triples = each_fitting(child, outcomes, nothing) do |path|
        pair_on(child, path)
      end
      added(triples)
    end

    # The possible paths of the decision named decision.
    def possible(decision)
      DecisionPaths.possible(@decisions.fetch(decision))
    end
  end
end
