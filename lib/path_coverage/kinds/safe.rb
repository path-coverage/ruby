require_relative 'base'

module PathCoverage
  module Kinds
    # A &. chain, eg user&.account&.owner, each receiver nil or
    # not, a nil one skipping the rest of the chain. As a decision of
    # its own its operands are its receivers; nested in another,
    # they are its receivers then its value, its last leaf. Each
    # receiver is wrapped in a present call, which passes it on
    # unchanged, so it is still evaluated just once.
    module Safe
      extend Base

      OPERATORS = [SAFE].freeze

      # The ways node, nested in a condition, can be evaluated,
      # its value its last leaf.
      def self.ways(node, fixed)
        chain(node.operands[0...-1], node.operands.last, fixed)
      end

      # The ways a &. chain decision can be evaluated, every operand
      # a receiver.
      def self.root_ways(node, fixed)
        chain(node.operands, nil, fixed)
      end

      # The ways a &. chain can be evaluated: each receiver not
      # nil going on to the next, a nil one ending the chain, its
      # value false; then, given a last leaf, the chain's value
      # as an operand of a condition, the ways it can be.
      def self.chain(receivers, last, fixed)
        first, *rest = receivers
        on = if !rest.empty? then chain(rest, last, fixed)
             elsif last then DecisionPaths.walk(last, fixed)
             else [[{}, true]]
             end
        present = on.map do |outcomes, value|
          [outcomes.merge(first => PRESENCE[0]), value]
        end
        return present if fixed[first] == :present

        [*present, [{ first => PRESENCE[1] }, false]]
      end

      # Its value in each column: false where a receiver was nil,
      # as the chain then gives nil, else its last leaf's.
      def self.value(_operator, operands)
        columns = operands.map { |operand| operand[:cells] }.transpose
        columns.map do |column|
          column.include?(PRESENCE[1]) ? false : column.last
        end
      end

      # The inserts for a &. chain decision: each receiver in a
      # present call, and the whole chain in a leave call that
      # enters it first. Eg user&.account becomes, in effect,
      # leave(enter(decision, 1),
      #       present(decision, 0, 0, user)&.account).
      def self.decision_inserts(decision, condition)
        leaves = condition.leaves
        name = decision.inspect
        enter = "PathCoverage.enter(#{name}, #{leaves.size})"
        call = "PathCoverage.leave(#{enter}, "
        extent = condition.extent
        command = condition.commands.include?(extent)
        presents(decision, leaves) +
          Rewriter.wrap(call, extent, command, :decision)
      end

      # The inserts wrapping each of leaves, a &. chain decision's,
      # in its present call.
      def self.presents(decision, leaves)
        leaves.each_with_index.flat_map do |range, index|
          opening = present(decision, index, 0)
          Rewriter.wrap(opening, range, false, :leaf)
        end
      end

      # Its leaves need present and chained calls.
      def self.own_calls?
        true
      end

      # { leaf range => the opening of its call } for the leaves of
      # chain nested in a decision whose leaves are leaves: a
      # receiver's present call, and the chain's value's chained
      # call, each told where its chain's leaves start.
      def self.calls(decision, chain, leaves)
        first = leaves.index(chain.operands.first)
        *receivers, value = chain.operands
        calls = receivers.to_h do |range|
          [range, present(decision, leaves.index(range), first)]
        end
        at = leaves.index(value)
        calls.merge(value => chained(decision, at, first))
      end

      # The opening of the chained call around the index-th leaf
      # of decision, a chain's value, its chain's leaves starting at
      # first.
      def self.chained(decision, index, first)
        "PathCoverage.chained(#{decision.inspect}, #{index}, " \
          "#{first}, "
      end

      # The opening of the present call around the index-th leaf
      # of decision, its chain's leaves starting at first.
      def self.present(decision, index, first)
        "PathCoverage.present(#{decision.inspect}, #{index}, " \
          "#{first}, "
      end

      # Its leaves' nodes, each after the first showing only what
      # it adds to the one before, eg account after user.
      # A leading &. is left out, as the chain's own row shows it.
      # The chain after its last leaf, eg owner in
      # user&.account&.owner, has no node: it decides no path, and
      # is called exactly where that leaf is not nil.
      def self.texted(source, condition, nodes)
        with_added(source, condition.operands, nodes)
      end

      # nodes, the nodes of a chain's leaves at ranges, each after
      # the first showing only what it adds to the one before.
      def self.with_added(source, ranges, nodes)
        nodes.each_with_index.map do |node, index|
          next node if index.zero?

          added = ranges[index - 1].end...ranges[index].end
          node.merge(text: shown(source, added))
        end
      end

      # The text of source at range, less any leading &.
      def self.shown(source, range)
        source.byteslice(range).delete_prefix('&.')
      end

      # The rows of its leaves, each under the one before, as each
      # is reached only when the one before is not nil.
      def self.rows(chain, indent)
        chain[:operands].each_with_index.map do |operand, depth|
          gaps = FoldBranches::GAP * depth
          branch = "#{indent}#{gaps}#{FoldBranches::ELL}"
          FoldRows.operand_row(operand, branch)
        end
      end
    end
  end
end
