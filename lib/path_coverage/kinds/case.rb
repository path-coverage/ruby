require_relative 'base'
require_relative 'chain'

module PathCoverage
  module Kinds
    # A case, its operands its whens' and else's arms, each when
    # trying its patterns in turn until one matches. Each pattern
    # is wrapped in a stand-in, which matches the case's subject
    # against it once, as the case would have.
    module Case
      extend Base

      OPERATORS = %w[case].freeze

      # The ways node can be evaluated: as the chain of its whens'
      # conditions.
      def self.ways(node, fixed)
        whens = node.operands.filter_map(&:body)
        Chain.ways(node.with(operands: whens), fixed)
      end

      # The inserts that wrap each pattern of a case decision in a
      # when_match call, its stand-in, which enters and leaves the
      # decision itself, as the case tries its patterns one by one;
      # its arms may return or raise, so no leave wraps it.
      def self.decision_inserts(decision, condition)
        size = condition.leaves.size
        condition.leaves.each_with_index.flat_map do |range, index|
          call = "PathCoverage.when_match(#{decision.inspect}, " \
                 "#{index}, #{size}, "
          Rewriter.wrap(call, range, false, :leaf)
        end
      end

      # Its node in a decision's tree from its arms, built in order so
      # its whens' patterns pair with path entries left to right:
      # a when is taken on each path one of its patterns matched,
      # and the else on each none did. A case's value is that of
      # no choice, so is nil.
      def self.node(source, condition, outcomes, leaves)
        matched = []
        operands = condition.operands.map do |arm|
          arm_node(source, arm, matched, [outcomes, leaves])
        end
        cells = Array.new(outcomes.size)
        { operator: 'case', cells:, operands: }
      end

      # One arm's node, its cells whether each column took it;
      # matched holds the cells of each when before it, and a
      # when's own are added.
      def self.arm_node(source, arm, matched, (outcomes, leaves))
        condition = arm.body
        body = if condition
                 DecisionTree.node(source, condition, outcomes,
                                   leaves)
               end
        matched << body[:cells].map { |cell| cell == true } if body
        cells = body ? matched.last : unmatched(matched, outcomes)
        text = DecisionTree.text_of(source, arm)
        { arm: arm.kind, text:, leaves: arm.leaves, cells:, body: }
      end

      # Whether each column matched none of its whens' patterns:
      # a when's cell is true where it matched.
      def self.unmatched(matched, outcomes)
        outcomes.each_index.map do |column|
          !matched.map { |taken| taken[column] }.include?(true)
        end
      end

      # Its patterns need pattern calls.
      def self.own_calls?
        true
      end

      # { pattern range => the opening of its pattern call } for
      # the patterns of inner, a case nested in a decision whose
      # leaves are leaves.
      def self.calls(decision, inner, leaves)
        inner.leaves.to_h do |range|
          index = leaves.index(range)
          [range,
           "PathCoverage.pattern(#{decision.inspect}, #{index}, "]
        end
      end
    end
  end
end
