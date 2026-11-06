require_relative 'base'
require_relative 'block'

module PathCoverage
  module Kinds
    # A leaf with decisions inside it, eg
    # ids.select { |i| i.odd? }.any? as an operand of an &&: its
    # operands are those decisions'
    # Conditions, which run as it does, then the leaf's own byte
    # range, whose outcome is its value.
    module Contains
      extend Base

      OPERATORS = [CONTAINS].freeze

      # The ways node can be evaluated: each way of every one of
      # the decisions inside it, then each way of the leaf itself, its
      # value the whole's.
      def self.ways(node, fixed)
        inner = node.operands[0...-1]
        before = inner.reduce([{}]) do |ways, decision|
          ways.product(DecisionPaths.walk(decision, fixed))
              .map { |outcomes, (more, _)| outcomes.merge(more) }
        end
        before.flat_map do |outcomes|
          leaf_ways(node, outcomes, fixed).map do |more, value|
            [outcomes.merge(more), value]
          end
        end
      end

      # The ways the leaf of node can be evaluated after the decisions
      # inside it took outcomes: the one outcome it must have then,
      # when known, else true or false.
      def self.leaf_ways(node, outcomes, fixed)
        range = node.operands.last
        known = known_outcome(node, outcomes, fixed)
        return DecisionPaths.leaf(range, fixed) if known.nil?

        [[{ range => known }, known]]
      end

      # The outcome the leaf of node must have after the decisions
      # inside it took outcomes, nil when it can have either: for
      # a call treated as nonempty, eg any?, whether its receiver
      # has items; for a leaf that is wholly one decision, eg a find,
      # that decision's value. Each only when the decision's kind can
      # tell. A nonempty call has no arguments, so its receiver is
      # the largest of those decisions, any other lying within it.
      def self.known_outcome(node, outcomes, fixed)
        *inner, range = node.operands
        if node.fixed[range] == :nonempty
          receiver = inner.max_by { |decision| decision.extent.size }
          return Block.items?(receiver, outcomes)
        end
        whole = inner.to_h do |decision|
          [decision.extent, decision]
        end[range]
        return nil if whole.nil?

        value_on(whole, outcomes, fixed)
      end

      # decision's value on its way that took outcomes, one of its
      # own, nil when its kind cannot tell. outcomes always hold
      # one of decision's ways, so one is always found.
      def self.value_on(decision, outcomes, fixed)
        DecisionPaths.walk(decision, fixed).each do |more, value|
          return value if more <= outcomes
        end
      end

      # Its value in each column: the leaf's own, its last operand.
      def self.value(_operator, operands)
        operands.last[:cells]
      end

      # nodes, labelled and texted so their rows read as the
      # leaf's code does.
      # Each decision inside the leaf is labelled with the leaf's text
      # before it, its operator, and its own opening, eg select {
      # for ids.select { |id| id.odd? }.any?, or ( || for
      # (a || b).any?.
      # The leaf is texted with the last decision's own closing, then
      # the leaf's text after that decision, eg }.any? or ).any?.
      def self.texted(source, condition, nodes)
        *inner, range = condition.operands
        starts = [range.begin, *inner.map do |decision|
          decision.extent.end
        end]
        labelled = inner.zip(starts,
                             nodes).map do |decision, at, node|
          node.merge(label: label(source, decision, at))
        end
        text = tail(source, inner.last, range)
        [*labelled, nodes.last.merge(text:)]
      end

      # decision's label inside a leaf: the leaf's text from byte at
      # up to decision, then decision's operator and its own opening.
      def self.label(source, decision, at)
        before = source.byteslice(at...decision.extent.begin).strip
        opening, = Kinds.of(decision.operator).brackets(source,
                                                        decision)
        [before, decision.operator,
         opening].reject(&:empty?).join(' ')
      end

      # The text of the leaf at range: the closing of last, the
      # last decision inside the leaf, then the leaf's text after it.
      def self.tail(source, last, range)
        _, closing = Kinds.of(last.operator).brackets(source, last)
        closing + source.byteslice(last.extent.end...range.end)
      end

      # The decisions inside it, then the leaf, as siblings, so each
      # decision's rows are drawn once, eg select { then }.any?.
      def self.unfold(node)
        node[:operands]
      end
    end
  end
end
