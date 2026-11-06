module PathCoverage
  # The part of the manifest's visitor that leaves out the decisions
  # of ignored operators, eg ignore '&&='. An ignored node is no
  # decision, though a decision inside it may be; nested in a
  # decision, it is a leaf. It relies on its includer's
  # @ignored, ternary? and safe_chain?.
  module ManifestIgnoring
    # The operator of each node type that always names one kind
    # of decision.
    NAMED = { unless_node: 'unless', case_node: 'case' }.freeze

    # True for a node whose operator is ignored.
    def ignored?(node)
      @ignored.include?(operator_of(node))
    end

    # The operator naming node's kind of decision, eg ?: for a
    # ternary or any? for a block method's call; nil for a
    # node with none.
    def operator_of(node)
      type = node.type
      return NAMED[type] if NAMED.key?(type)
      return ternary?(node) ? '?:' : 'if' if type == :if_node
      return call_operator(node) if type == :call_node

      node.respond_to?(:operator) ? node.operator : nil
    end

    # The operator of a call: &. for a &. chain, else its
    # method's name, eg any?.
    def call_operator(node)
      safe_chain?(node) ? '&.' : node.name.to_s
    end
  end
end
