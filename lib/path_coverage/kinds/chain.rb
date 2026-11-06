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
      # one its operator goes on with.
      def self.ways(node, fixed)
        first, *rest = node.operands
        goes_on = CONTINUES_ON.fetch(node.operator)
        rest.reduce(DecisionPaths.walk(first, fixed)) do |all, later|
          all.flat_map do |outcomes, value|
            next [[outcomes, value]] unless value == goes_on

            DecisionPaths.walk(later, fixed).map do |more, after|
              [outcomes.merge(more), after]
            end
          end
        end
      end

      # Its value in each column: the last operand it reached.
      def self.value(_operator, operands)
        operands.map { |operand| operand[:cells] }
                .transpose.map { |column| column.compact.last }
      end
    end
  end
end
