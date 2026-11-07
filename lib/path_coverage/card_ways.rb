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
  # gives knows it. A block's body counts once.
  # Each way also notes the outcome it gives each leaf that
  # StableLeaves finds, by its local's name, and two ways joined
  # one after the other that give one name both outcomes are no
  # way, as no call can take them.
  # The fold is in one of WayAlgebras: Counted counts the ways,
  # by default; Labelled gives the paths taken on any of them, and
  # Listed lists them.
  class CardWays
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
    # Manifest.decisions gives them.
    def self.card(source, decisions, rows,
                  algebra = WayAlgebras::Counted)
      places = CardTree.nested(source, decisions, rows)
      new(source, rows, places, decisions, algebra).total
    end

    # The fold of rows, a card's in source, placed as places has
    # them, each decision row's Condition among decisions, its ways
    # in algebra, each step of it a tally of them, as
    # WayAlgebras::Tallied has them, assigning the leaves
    # StableLeaves finds.
    def initialize(source, rows, places, decisions, algebra)
      @source = source
      @rows = rows.to_h { |row| [CardTree.key_of(row), row] }
      @places = places
      @decisions = decisions
      @ways = WayAlgebras::Tallied.new(algebra)
      @children = places.keys.group_by { places[_1]['parent'] }
      @names = StableLeaves.of(source, decisions, rows)
    end

    # The ways through the card, in its algebra: its top rows'
    # pairs, one after another, those that go on and those that
    # leave, whatever their assignments.
    def total
      tops = @children.fetch(nil, []).map { |key| pair_of(key) }
      @ways.total(@ways.plus(*sequence(tops)))
    end

    # The pair of rows one after another, from their pairs: the
    # ways that go on through them all, and those that leave at
    # one of them, having gone on through every one before it.
    def sequence(pairs)
      start = [@ways.one, @ways.zero]
      pairs.reduce(start) do |(on, left), (more, out)|
        through = @ways.times(on, out)
        [@ways.times(on, more), @ways.plus(left, through)]
      end
    end

    # The pair of the row keyed key: a decision's adds up its paths'
    # pairs; any other row is a return or a raise, as no other is
    # a row, so leaves, at its one path.
    def pair_of(key)
      row = @rows[key]
      leaves = [@ways.zero, @ways.unit([key, 0])]
      return leaves if row.decision.nil?

      pairs = possible(row.decision).each_index.map do |path|
        pair_on(key, path)
      end
      added(pairs)
    end

    # The pair of the decision row keyed key on its path at index
    # path: that path taken, then the rows it runs on that path,
    # one after another, each given that path's outcomes; every
    # way of it leaving when the path takes an arm that leaves.
    def pair_on(key, path)
      outcomes = possible(@rows[key].decision)[path]
      pairs = running(key, path).map do |child|
        child_pair(child, outcomes)
      end
      own = own(key, path, outcomes)
      on, left = sequence(pairs).map { @ways.times(own, _1) }
      return [on, left] unless leaving(key).include?(path)

      [@ways.zero, @ways.plus(on, left)]
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
      place = @places[child]
      gives = place['gives']
      return pair_of(child) if gives.nil?

      fits = [nil, outcome_of(outcomes, place)]
      none = [@ways.zero, @ways.zero]
      pairs = gives.each_index.map do |path|
        fits.include?(gives[path]) ? pair_on(child, path) : none
      end
      added(pairs)
    end

    # The outcome on a parent's path, outcomes, of the leaf place
    # names.
    def outcome_of(outcomes, place)
      outcomes[place['leaf']]
    end

    # The indices of the paths of the decision row keyed key that take
    # an arm whose code returns or raises.
    def leaving(key)
      decision = @decisions.fetch(@rows[key].decision)
      regions = CardTree.regions_of(@source, key, decision)
      regions.select(&:leaves).flat_map(&:on)
    end

    # pairs added up, each part on its own; no ways for no pairs.
    def added(pairs)
      none = [@ways.zero, @ways.zero]
      pairs.reduce(none) do |(on, left), (more, out)|
        [@ways.plus(on, more), @ways.plus(left, out)]
      end
    end

    # The possible paths of the decision named decision.
    def possible(decision)
      DecisionPaths.possible(@decisions.fetch(decision))
    end
  end
end
