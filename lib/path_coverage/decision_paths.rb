require_relative 'condition'
require_relative 'kinds'

module PathCoverage
  # The paths an evaluation of a decision can take, worked out
  # from its condition alone: the outcome of each leaf, in leaf
  # order, nil for a leaf that evaluation never reaches.
  module DecisionPaths
    # Every possible path through decision's condition, true before
    # false, as its kind gives the ways a decision of it can be
    # evaluated.
    def self.possible(decision)
      ways = Kinds.of(decision.operator).root_ways(decision,
                                                   decision.fixed)
      ways.map do |outcomes, _value|
        decision.leaves.map { |range| outcomes[range] }
      end
    end

    # Example: [false, true, false, true, false] for an any?.
    # decision's value on each of its possible paths, in the order
    # possible gives them, nil where not known.
    def self.values(decision)
      ways = Kinds.of(decision.operator).root_ways(decision,
                                                   decision.fixed)
      ways.map(&:last)
    end

    # [[{ leaf range => outcome }, value], ...] for each way
    # node can be evaluated, value being the outcome of node as
    # a whole, as its kind gives them; fixed is the decision's
    # { leaf range => its one outcome }.
    def self.walk(node, fixed)
      return leaf(node, fixed) unless node.is_a?(Condition)

      Kinds.of(node.operator).ways(node, fixed)
    end

    # The ways a leaf can be evaluated: true, then false, or
    # its one outcome alone when it is fixed.
    def self.leaf(range, fixed)
      only = fixed[range]
      outcomes = only ? [only == :truthy] : [true, false]
      outcomes.map { |outcome| [{ range => outcome }, outcome] }
    end
  end
end
