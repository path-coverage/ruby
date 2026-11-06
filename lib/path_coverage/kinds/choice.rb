require_relative 'base'

module PathCoverage
  module Kinds
    # The ways and value of a condition whose predicate picks an
    # arm, which Choice and Write share.
    module Arms
      # The ways node can be evaluated: each way of its predicate,
      # then each way of the condition the arm it picks is, if
      # that arm is one; one with no else arm picks none. Its
      # value is that of no choice, so is nil.
      def ways(node, fixed)
        predicate, then_arm, else_arm = node.operands
        then_on = THEN_ON[node.operator]
        DecisionPaths.walk(predicate,
                           fixed).flat_map do |outcomes, value|
          body = (value == then_on ? then_arm : else_arm)&.body
          next [[outcomes, nil]] if body.nil?

          DecisionPaths.walk(body, fixed).map do |more, _|
            [outcomes.merge(more), nil]
          end
        end
      end

      # Its value in each column: its taken arm's body's, nil for
      # a plain arm.
      def value(_operator, operands)
        _, *arms = operands
        bodies = arms.map { |arm| arm[:body]&.fetch(:cells) }
        arms.first[:cells].each_index.map do |column|
          taken = arms.index { |arm| arm[:cells][column] }
          taken && bodies[taken]&.fetch(column)
        end
      end
    end

    # A condition whose predicate picks an arm: a ternary, an if
    # or an unless.
    module Choice
      extend Base
      extend Arms

      OPERATORS = CHOICES

      # What its decision's leave call wraps: an if's or an unless's
      # predicate, a leaf's byte range or a nested Condition, as
      # its path is decided there and its arms are statements that
      # may return or raise; a ternary as a whole.
      def self.trailed(condition)
        return condition if condition.operator == '?:'

        condition.operands.first
      end

      # The name of one of a ternary's arms: ? or :, then its
      # condition's operator, or its text for a plain arm.
      def self.arm_label(arm)
        mark = arm[:arm] == :then ? '?' : ':'
        body = arm[:body]
        "#{mark} #{body ? body[:operator] : arm[:text]}"
      end
    end
  end
end
