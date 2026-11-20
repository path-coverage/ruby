module PathCoverage
  # The loops of a flow. forks is { loop's name => [its bytes, its
  # body's] }, as LoopForks gives them. Each loop is a scope: a
  # next or a break in its body ends a pass, and the way goes on
  # after the loop. When loops are decisions, each loop is also a
  # fork. Its path 0 is no item. Its path 1 is at least one item,
  # and runs its body, which holds its rows. A loop is placed by
  # its bytes, as a row that is no decision is. The module
  # functions place loops, for PathsTree. The instance methods fold
  # them, for PathsWays, which includes this module.
  module PathsForks
    # The region of each loop of forks, its body, run on its path
    # 1. Then the regions of each rescue fork of rescues, as
    # PathsRescues gives them.
    def self.regions(forks, rescues)
      forks.map do |name, (_, body)|
        PathsTree::Region.new(owner: PathsTree.key_at(name),
                              range: body, arm: 'body', on: [1],
                              leaf: nil, leaves: nil)
      end + PathsRescues.regions(rescues)
    end

    # places, { key => its place }, a flow's rows', with the place
    # of each scope too, among regions. The scopes are each loop of
    # forks and each rescue fork of rescues. All are in the order
    # they start. With no scope it is places alone.
    def self.placed(places, (forks, rescues), regions)
      spans = forks.transform_values(&:first)
                   .merge(rescues.transform_values { _1[1] })
      return places if spans.empty?

      scopes = spans.to_h do |name, span|
        key = PathsTree.key_at(name)
        [key, PathsTree.placed(key, span, regions, nil)]
      end
      merged = places.merge(scopes)
      merged.sort_by { _1[0].split(':').map(&:to_i) }.to_h
    end

    # The parts of the loop keyed key, which is placed but is no
    # row. Its body's rows run one after another, walked once. A
    # pass ended by a next or a break goes on after the loop. When
    # loops fork, the loop either makes no pass, or makes at least
    # one and runs its body.
    def fork_pair(key)
      body = rejoined(sequence(running(key, 1).map { pair_of(_1) }))
      return body unless @forking

      own = @ways.unit([key, 1])
      some = body.map { @ways.times(own, _1) }
      added([[@ways.unit([key, 0]), *nothing.drop(1)], some])
    end

    # The parts of ways through a loop's body, [on, returned, raised,
    # passed], once its scope ends. The ways that ended a pass by a
    # next or a break join those that go on.
    def rejoined((on, returned, raised, passed))
      [@ways.plus(on, passed), returned, raised, @ways.zero]
    end

    # many, each a fold's parts, added up part by part. No parts
    # add up to no ways.
    def added(many)
      many.reduce(nothing) do |sum, parts|
        sum.zip(parts).map { @ways.plus(*_1) }
      end
    end

    # The parts, [on, returned, raised, passed], of no ways.
    def nothing = Array.new(4) { @ways.zero }
  end
end
