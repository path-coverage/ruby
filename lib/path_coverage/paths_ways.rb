require_relative 'paths_fitting'
require_relative 'paths_leaving'
require_relative 'paths_rescues'
require_relative 'paths_tree'
require_relative 'manifest'
require_relative 'method_statements'
require_relative 'decision_paths'
require_relative 'stable_leaves'
require_relative 'way_algebras'

module PathCoverage
  # The ways one call can go through each flow, folded over its
  # tree, as PathsTree places its rows. Each row gives a pair,
  # [ways that go on, ways that leave the method]: a return or a
  # raise leaves, and so does each path of a decision taking an
  # arm that returns or raises, eg return 0 if a. Rows one after
  # another multiply, but only the ways that go on reach the next
  # row; a decision adds up its paths, each with the rows it runs
  # on that path one after another; and a row that is the whole of
  # a leaf counts only those of its paths that give the leaf the
  # outcome the path has, so no impossible way is counted where
  # gives knows it. A block's body counts once, unless the block
  # forks, as PathsForks folds it.
  # Each way also notes the outcome it gives each leaf that
  # StableLeaves finds, by its local's name, and two ways joined
  # one after the other that give one name both outcomes are no
  # way, as no call can take them.
  # The fold is in one of WayAlgebras: Counted counts the ways,
  # by default; Labelled gives the paths taken on any of them, and
  # Listed lists them.
  class PathsWays
    include PathsFitting
    include PathsForks
    include PathsLeaving
    include PathsRescues

    # Example: { "k.rb:1:0" => 3 } for def f(a, b), return 0 if a,
    # then a ?: of b: 1 way leaves, 2 go on.
    # { def decision => its ways, in algebra } for each def in
    # source, its decisions those of no settings.
    def self.of(source, path, algebra = WayAlgebras::Counted)
      decisions = Manifest.decisions(source, path)
      flows = MethodStatements.of(source, path, decisions)
      flows.transform_values do |rows|
        flow(source, decisions, rows, algebra)
      end
    end

    # The ways through a flow of rows in source, in algebra,
    # decisions being { decision => Condition }, as
    # Manifest.decisions gives them. folding is [stable, forks,
    # rescues, forking]. With stable false, the ways include those
    # no call can take, as no leaf is then assigned. Each loop of
    # forks, as LoopForks gives them, is a scope that a next or a
    # break ends a pass of. When forking, each loop is a fork too,
    # labelled [its key, 0] for 0 items and [its key, 1] for 1+
    # items, then its body's rows, walked once. Each rescue fork of
    # rescues, a def's, forks the flow.
    def self.flow(source, decisions, rows,
                  algebra = WayAlgebras::Counted,
                  folding = [true, {}, {}, false])
      stable, forks, rescues, forking = folding
      places = PathsTree.nested(source, decisions, rows,
                                [forks, rescues])
      names = stable ? StableLeaves.of(source, decisions, rows) : {}
      new(source, rows, places, decisions,
          [algebra, names, rescues, forking]).total
    end

    # The fold of rows, a flow's in source, placed as places has
    # them. Each decision row's Condition is in decisions. folding
    # is [algebra, names, rescues, forking]. Its ways are in
    # algebra, and each step of it tallies them, as
    # WayAlgebras::Tallied does. names assigns leaves, as
    # StableLeaves finds them. rescues are the def's rescue forks,
    # as RescueForks gives them. forking says whether loops fork.
    def initialize(source, rows, places, decisions,
                   (algebra, names, rescues, forking))
      @source = source
      @rows = rows.to_h { |row| [PathsTree.key_of(row), row] }
      @places = places
      @decisions = decisions
      @ways = WayAlgebras::Tallied.new(algebra)
      @children = places.keys.group_by { places[_1]['parent'] }
      @names = names
      @rescues = PathsRescues.counts(rescues)
      @forking = forking
    end

    # The ways through the flow, in its algebra. Its top rows run
    # one after another. Every way counts, whether it goes on or
    # leaves, whatever its assignments.
    def total
      tops = @children.fetch(nil, []).map { |key| pair_of(key) }
      all = sequence(tops)
      @ways.total(all.reduce { |sum, ways| @ways.plus(sum, ways) })
    end

    # The parts of rows run one after another, from each row's
    # parts. The ways that go on pass through every row. A way
    # that leaves at one row has gone on through each row before
    # it.
    def sequence(many)
      start = [@ways.one, *nothing.drop(1)]
      many.reduce(start) do |(on, *out), (more, *leave)|
        through = leave.map { @ways.times(on, _1) }
        [@ways.times(on, more),
         *out.zip(through).map { @ways.plus(*_1) }]
      end
    end

    # The parts of the row keyed key. A decision adds up its
    # paths' parts. Any other row is a statement that leaves, eg
    # a return or a next, so it leaves by its word on its one path.
    def pair_of(key)
      return rescue_pair(key) if @rescues.key?(key)
      return fork_pair(key) unless @rows.key?(key)

      row = @rows[key]
      return left(row.top, @ways.unit([key, 0])) if row.decision.nil?

      many = possible(row.decision).each_index.map do |path|
        pair_on(key, path)
      end
      added(many)
    end

    # The parts of the decision row keyed key on its path at index
    # path. The path is taken, then the rows it runs one after
    # another, each given that path's outcomes. When the path's arm
    # leaves, every way of it leaves, by the arm's word.
    def pair_on(key, path)
      outcomes = possible(@rows[key].decision)[path]
      many = running(key, path).map do |child|
        child_pair(child, outcomes)
      end
      own = own(key, path, outcomes)
      ways = sequence(many).map { @ways.times(own, _1) }
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

    # The parts of the row keyed child. outcomes is its parent's
    # path's outcomes. A row that gives nothing keeps all its
    # paths. Otherwise only the paths that fit outcomes count, as
    # PathsFitting decides.
    def child_pair(child, outcomes)
      return pair_of(child) if @places[child]['gives'].nil?

      many = each_fitting(child, outcomes, nothing) do |path|
        pair_on(child, path)
      end
      added(many)
    end

    # The possible paths of the decision named decision.
    def possible(decision)
      DecisionPaths.possible(@decisions.fetch(decision))
    end
  end
end
