require_relative 'card_tree'
require_relative 'manifest'
require_relative 'method_statements'
require_relative 'decision_paths'

module PathCoverage
  # The number of ways one call can go through each card, folded
  # over its tree, as CardTree places its rows. Each row gives a
  # pair, [ways that go on, ways that leave the method]: a return
  # or a raise leaves, and so does each path of a decision taking an
  # arm that returns or raises, eg return 0 if a. Rows one after
  # another multiply, but only the ways that go on reach the next
  # row; a decision adds up its paths, each with the rows it runs on
  # that path one after another; and a row that is the whole of a
  # leaf counts only those of its paths that give the leaf the
  # outcome the path has, so no impossible way is counted where
  # gives knows it. A block's body counts once.
  class CardWays
    # Example: { "k.rb:1:0" => 3 } for def f(a, b), return 0 if a,
    # then a ?: of b: 1 way leaves, 2 go on.
    # { def decision => its ways } for each def in source, its
    # decisions those of no settings.
    def self.of(source, path)
      decisions = Manifest.decisions(source, path)
      cards = MethodStatements.of(source, path, decisions)
      cards.transform_values { |rows| card(source, decisions, rows) }
    end

    # The ways through a card of rows in source, decisions being
    # { decision => Condition }, as Manifest.decisions gives them.
    def self.card(source, decisions, rows)
      places = CardTree.nested(source, decisions, rows)
      new(source, rows, places, decisions).total
    end

    # The pair of rows one after another, from their pairs: the
    # ways that go on through them all, and those that leave at
    # one of them, having gone on through every one before it.
    def self.sequence(pairs)
      pairs.reduce([1, 0]) do |(on, left), (more, leaving)|
        [on * more, left + (on * leaving)]
      end
    end

    # The fold of rows, a card's in source, placed as places has
    # them, each decision row's Condition among decisions.
    def initialize(source, rows, places, decisions)
      @source = source
      @rows = rows.to_h { |row| [CardTree.key_of(row), row] }
      @places = places
      @decisions = decisions
      @children = places.keys.group_by { places[_1]['parent'] }
    end

    # The ways through the card: its top rows' pairs, one after
    # another, those that go on and those that leave.
    def total
      tops = @children.fetch(nil, []).map { |key| pair_of(key) }
      CardWays.sequence(tops).sum
    end

    # The pair of the row keyed key: a decision's adds up its paths'
    # pairs; any other row is a return or a raise, as no other is
    # a row, so leaves.
    def pair_of(key)
      row = @rows[key]
      return [0, 1] unless row.decision

      pairs = possible(row.decision).each_index.map do |path|
        pair_on(key, path)
      end
      added(pairs)
    end

    # The pair of the decision row keyed key on its path at index
    # path: the rows it runs on that path, one after another, each
    # given that path's outcomes; every way of it leaving when the
    # path takes an arm that leaves.
    def pair_on(key, path)
      outcomes = possible(@rows[key].decision)[path]
      pairs = running(key, path).map do |child|
        child_pair(child, outcomes)
      end
      pair = CardWays.sequence(pairs)
      leaving(key).include?(path) ? [0, pair.sum] : pair
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
      pairs = gives.each_index.map do |path|
        fits.include?(gives[path]) ? pair_on(child, path) : [0, 0]
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
      left = regions.group_by do |region|
        region.arm && @source.byteslice(region.range).match?(LEAVES)
      end
      left.fetch(true, []).flat_map(&:on)
    end

    # pairs added up, each part on its own.
    def added(pairs)
      pairs.reduce([0, 0]) { |(a, b), (c, d)| [a + c, b + d] }
    end

    # The possible paths of the decision named decision.
    def possible(decision)
      DecisionPaths.possible(@decisions.fetch(decision))
    end
  end
end
