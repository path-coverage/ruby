module PathCoverage
  # How ways leave a flow. PathsWays includes it. A return or a
  # throw returns, and no rescue catches it. A raise or a fail
  # raises, and a rescue can catch it. A next, a break or a retry
  # ends its pass, and the way goes on after its loop.
  module PathsLeaving
    # Where the ways that leave by each word go, as an index into a
    # fold's parts, [on, returned, raised, passed].
    PARTS = { 'return' => 1, 'throw' => 1, 'raise' => 2, 'fail' => 2,
              'next' => 3, 'break' => 3, 'retry' => 3 }.freeze

    # { path index => word } for the decision row keyed key. It
    # holds each path whose arm leaves, with the word it leaves
    # by, eg return or raise.
    def leaving(key)
      decision = @decisions.fetch(@rows[key].decision)
      regions = PathsTree.regions_of(@source, key, decision)
      regions.select(&:leaves).flat_map do |region|
        region.on.map { [_1, region.leaves] }
      end.to_h
    end

    # The parts of ways, [on, returned, raised, passed]. With word
    # nil they are unchanged. Otherwise every way leaves, and those
    # that went on leave by word.
    def leaving_by((on, *out), word)
      return [on, *out] if word.nil?

      all = left(word, on).drop(1).zip(out).map { @ways.plus(*_1) }
      [@ways.zero, *all]
    end

    # The parts holding ways, put where word sends them, as PARTS
    # says. Every other part is empty.
    def left(word, ways)
      part = PARTS.fetch(word)
      (0..3).map { |index| index == part ? ways : @ways.zero }
    end
  end
end
