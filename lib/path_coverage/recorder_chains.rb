require_relative 'condition'

module PathCoverage
  # The part of the recorder that notes &. chains. It relies on
  # its includer's counts, record and trails.
  module RecorderChains
    # Notes value, the index-th leaf of decision, a &. receiver, as
    # not nil or nil, and returns it unchanged; it counts truthy
    # when not nil. A receiver after a nil one in its chain,
    # whose leaves start at first, was never reached, as Ruby
    # skips the rest of the chain, so is not noted.
    def present(decision, index, first, value)
      return value unless reached?(decision, first, index)

      @counts[[decision, index]][value.nil? ? :falsy : :truthy] += 1
      trail = trails(decision).last
      trail.outcomes[index] = PRESENCE[value.nil? ? 1 : 0] if trail
      value
    end

    # Notes value, a &. chain's value as the index-th leaf of
    # decision, as record does, when every receiver of the chain,
    # whose leaves start at first, was not nil; returns value
    # unchanged.
    def chained(decision, index, first, value)
      return value unless reached?(decision, first, index)

      record(decision, index, value)
    end

    # True when decision's current evaluation reached its index-th
    # leaf: every leaf of its chain before it, from first, was
    # not nil. An evaluation with no trail, eg in another fiber,
    # is taken to reach it.
    def reached?(decision, first, index)
      trail = trails(decision).last
      trail.nil? || trail.outcomes[first...index].all?(PRESENCE[0])
    end
  end
end
