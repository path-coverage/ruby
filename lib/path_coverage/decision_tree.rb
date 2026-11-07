require_relative 'condition'
require_relative 'kinds'

module PathCoverage
  # The tree shown under a decision's line on its file's page: a
  # grid whose columns are the decision's paths, never taken first.
  module DecisionTree
    # { operator:, counts:, cells:, operands: } for one decision,
    # from its paths, [{path:, count:}, ...]. counts are the
    # columns' counts. Every node has cells, one per column: a
    # leaf { text:, cells: } its outcome, nil where unreached;
    # a condition { operator:, cells:, operands: } its value;
    # an arm { arm:, text:, cells:, body: } whether the column
    # took it, body being its condition's tree, nil for a plain
    # arm. Texts are cut from source at the manifest's ranges.
    # An elsif's tree is labelled elsif, as it is written.
    def self.of(source, condition, paths)
      columns = paths.sort_by.with_index do |taken, i|
        [taken[:count].zero? ? 0 : 1, i]
      end
      tree = built(source, condition, columns.map { _1[:path] })
      tree.merge(counts: columns.map { |taken| taken[:count] })
    end

    # The tree of condition with no counts, a column for each of
    # outcomes, each path's outcomes, in the order given.
    def self.built(source, condition, outcomes)
      tree = node(source, condition, outcomes, (0..).each)
      return tree unless elsif?(source, condition)

      tree.merge(label: 'elsif')
    end

    # True for an if decision written as an elsif: an if's extent
    # starts at its keyword.
    def self.elsif?(source, condition)
      condition.operator == 'if' &&
        source.byteslice(condition.extent.begin, 5) == 'elsif'
    end

    # The tree of condition, as its kind builds it, each leaf
    # taking the next index of leaves, so leaves pair with path
    # entries left to right.
    def self.node(source, condition, outcomes, leaves)
      kind = Kinds.of(condition.operator)
      kind.node(source, condition, outcomes, leaves)
    end

    # condition's operands' nodes, leaves and nested conditions
    # built in order, its arms left for arms to build after.
    def self.operands_of(source, condition, outcomes, leaves)
      nodes = condition.operands.map do |operand|
        case operand
        when Condition then node(source, operand, outcomes, leaves)
        when Arm then operand
        else leaf(source, operand, outcomes, leaves.next)
        end
      end
      Kinds.of(condition.operator).texted(source, condition, nodes)
    end

    # condition's node from its operands' nodes, its ternary
    # arms built in order after its predicate, as each arm's
    # cells follow from the predicate's.
    def self.arms(source, condition, operands, outcomes, leaves)
      predicate = operands.first
      operands = operands.map do |operand|
        next operand unless operand.is_a?(Arm)

        decided = [predicate[:cells], THEN_ON[condition.operator]]
        arm(source, operand, decided, outcomes, leaves)
      end
      operator = condition.operator
      cells = Kinds.of(operator).value(operator, operands)
      { operator: condition.operator, cells:, operands: }
    end

    # An arm's text, nil for one with no statements.
    def self.text_of(source, arm)
      arm.extent ? source.byteslice(arm.extent) : nil
    end

    # One arm of a ternary, an if or an unless: its text, nil
    # for an arm with no statements, whether each column took
    # it, from the predicate's cells and the outcome on which
    # its choice takes its then arm, and the tree of its
    # condition.
    def self.arm(source, arm, (decided, then_on), outcomes, leaves)
      picked = arm.kind == :then ? then_on : !then_on
      body = arm.body ? node(source, arm.body, outcomes, leaves) : nil
      {
        arm: arm.kind, text: text_of(source, arm), leaves: arm.leaves,
        cells: decided.map { |outcome| outcome == picked }, body:
      }
    end

    # One leaf's text and its outcome in each column.
    def self.leaf(source, range, outcomes, index)
      {
        text: source.byteslice(range),
        cells: outcomes.map { |path| path[index] }
      }
    end
  end
end
