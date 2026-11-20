module PathCoverage
  # How ways leave a card, for CardWays, which includes it: a
  # return or a throw returns, which no rescue catches; a raise or
  # a fail raises, which a rescue can.
  module CardLeaving
    # The words of the statements that leave by raising.
    RAISES = %w[raise fail].freeze

    # { path index => word } of the paths of the decision row keyed
    # key that take an arm whose code leaves, by the word it leaves
    # by, eg return or raise.
    def leaving(key)
      decision = @decisions.fetch(@rows[key].decision)
      regions = CardTree.regions_of(@source, key, decision)
      regions.select(&:leaves).flat_map do |region|
        region.on.map { [_1, region.leaves] }
      end.to_h
    end

    # The triple of ways, [on, returned, raised], as they are
    # for word nil; else all of them leaving, those that go on by
    # word, eg return or raise.
    def leaving_by((on, *out), word)
      return [on, *out] if word.nil?

      all = left(word, on).drop(1).zip(out).map { @ways.plus(*_1) }
      [@ways.zero, *all]
    end

    # The triple of ways, leaving by word: raised for a raise or a
    # fail, which a rescue can catch; else returned, eg a return or
    # a throw, which none can.
    def left(word, ways)
      return [@ways.zero, @ways.zero, ways] if RAISES.include?(word)

      [@ways.zero, ways, @ways.zero]
    end
  end
end
