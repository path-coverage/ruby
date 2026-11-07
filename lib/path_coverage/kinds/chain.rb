require_relative 'base'

module PathCoverage
  module Kinds
    # A chain of one operator, eg a && b && c, or a when's
    # patterns, each operand reached only while every one before
    # it gave the outcome its operator goes on with.
    module Chain
      extend Base

      OPERATORS = %w[&& and || or when].freeze

      # The outcome of an operand on which each operator goes on
      # to its next operand; any other ends the chain there. A
      # when's patterns, and a case's whens, stop at a match.
      CONTINUES_ON = {
        '&&' => true, 'and' => true, '||' => false, 'or' => false,
        'when' => false, 'case' => false
      }.freeze

      # The ways node can be evaluated: each way of its first
      # operand, going on to the next while each outcome is the
      # one its operator goes on with; a way that reaches an
      # operand that leaves the method, eg return t in
      # x or return t, ends there, with no value.
      def self.ways(node, fixed)
        first, *rest = node.operands
        goes_on = CONTINUES_ON.fetch(node.operator)
        rest.reduce(DecisionPaths.walk(first, fixed)) do |all, later|
          all.flat_map { |way| onward(way, later, goes_on, fixed) }
        end
      end

      # The ways a way so far goes on to at the operand later: the
      # way as it is, when its value is not the one its operator
      # goes on with; ended with no value, when later leaves the
      # method; else each way of later after it.
      def self.onward((outcomes, value), later, goes_on, fixed)
        return [[outcomes, value]] unless value == goes_on
        return [[outcomes, nil]] if later.is_a?(Arm)

        DecisionPaths.walk(later, fixed).map do |more, after|
          [outcomes.merge(more), after]
        end
      end

      # Its value in each column: the last operand it reached, an
      # operand that leaves the method giving none.
      def self.value(_operator, operands)
        operands.map { _1[:cells] unless _1.key?(:arm) }.compact
                .transpose.map { |column| column.compact.last }
      end

      # What its leave call wraps: the whole of it, or, for one
      # that ends in an operand that leaves the method, eg
      # x or return t, the operands before that one, so its path
      # is counted before the method is left.
      def self.trailed(condition)
        *before, last = condition.operands
        return condition unless last.is_a?(Arm)

        start = span(before.first).begin
        condition.with(operands: before,
                       extent: start...span(before.last).end)
      end

      # The byte range of operand, a leaf's range or a nested
      # condition's extent.
      def self.span(operand)
        operand.is_a?(Condition) ? operand.extent : operand
      end
    end
  end
end
