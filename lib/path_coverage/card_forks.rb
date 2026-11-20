module PathCoverage
  # How the loops of a card fork when loops are decisions, each of
  # forks being { loop's name => [its bytes, its body's] }, as
  # LoopForks gives them: a loop is placed as a row that is no
  # decision is, by its bytes; its body is a region of it run on
  # its path 1, at least one item, so holds its rows; its path 0
  # is no item. Its module functions place it, for CardTree; its
  # instance methods fold it, for CardWays, which includes it.
  module CardForks
    # The region of each loop of forks: its body, run on its path
    # 1.
    def self.regions(forks)
      forks.map do |name, (_, body)|
        CardTree::Region.new(owner: CardTree.key_at(name),
                             range: body, arm: 'body', on: [1],
                             leaf: nil, leaves: nil)
      end
    end

    # places, { key => its place }, a card's rows', with the place
    # of each loop of forks too, among regions, all in the order
    # they start; places alone with no loop.
    def self.placed(places, forks, regions)
      return places if forks.empty?

      loops = forks.to_h do |name, (span, _)|
        key = CardTree.key_at(name)
        [key, CardTree.placed(key, span, regions, nil)]
      end
      merged = places.merge(loops)
      merged.sort_by { _1[0].split(':').map(&:to_i) }.to_h
    end

    # The pair of the loop keyed key, placed but no row: no pass,
    # going on, or at least one, then the rows of its body one
    # after another, walked once.
    def fork_pair(key)
      triples = running(key, 1).map { pair_of(_1) }
      own = @ways.unit([key, 1])
      some = sequence(triples).map { @ways.times(own, _1) }
      added([[@ways.unit([key, 0]), @ways.zero, @ways.zero], some])
    end

    # triples, [on, returned, raised], added up, each part on its
    # own; no ways for no triples.
    def added(triples)
      triples.reduce(nothing) do |sum, triple|
        sum.zip(triple).map { @ways.plus(*_1) }
      end
    end

    # The triple of no ways.
    def nothing = [@ways.zero, @ways.zero, @ways.zero]
  end
end
