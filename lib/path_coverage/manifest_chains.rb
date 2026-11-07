require_relative 'condition'

module PathCoverage
  # The part of the manifest's visitor that builds the decisions of
  # safe-navigation chains, eg user&.account&.owner. It relies
  # on its includer's extent_of.
  module ManifestChains
    # The calls of node's chain, outermost first, eg owner then
    # account for user&.account&.owner; none for a node that is
    # no call.
    def chain_calls(node)
      calls = []
      while node&.type == :call_node
        calls << node
        node = node.receiver
      end
      calls
    end

    # True for a call whose chain has a &. in it, eg
    # user&.name.upcase.
    def safe_chain?(node)
      chain_calls(node).any?(&:safe_navigation?)
    end

    # A call that is a decision as a Condition: a &. chain's, or a
    # block method call's. It relies on its includer's
    # block_condition.
    def call_condition(node)
      return block_condition(node) unless safe_chain?(node)

      chain_condition(node, value: false)
    end

    # A &. chain as a Condition named &.: its leaves are the
    # receivers of its &. calls, innermost first, each nil or
    # not nil, and, with value, the whole chain's value last, as
    # when it is an operand of an && or an if's predicate. Any
    # decision in a call's arguments or block, or in the chain's
    # first receiver, is a decision of its own. A chain that is no
    # bare argument, eg a command call, is noted among the
    # decision's commands, to be parenthesised.
    def chain_condition(node, value:)
      calls = chain_calls(node)
      visit_chain(calls)
      safe = calls.select(&:safe_navigation?).reverse
      receivers = safe.map { |call| receiver_of(call) }
      extent = extent_of(node)
      @notes[:commands] << extent if Manifest.bare_less?(node)
      operands = value ? [*receivers, extent] : receivers
      Condition.new(operator: SAFE, operands:, extent:)
    end

    # The byte range of a &. call's receiver, noted among its
    # decision's fixed leaves as :present, never nil, when it is a
    # call to a method treated as present.
    def receiver_of(call)
      receiver = call.receiver
      range = extent_of(receiver)
      named = receiver.type == :call_node &&
              @present.include?(receiver.name.to_s)
      @notes[:fixed][range] = :present if named
      range
    end

    # Visits the decisions inside a chain's calls' arguments and
    # blocks, and inside its first receiver, eg (a || b) in
    # (a || b)&.size, but never a call of the chain itself.
    def visit_chain(calls)
      calls.each do |call|
        [call.arguments, call.block].compact.each { _1.accept(self) }
      end
      calls.last.receiver&.accept(self)
    end
  end
end
