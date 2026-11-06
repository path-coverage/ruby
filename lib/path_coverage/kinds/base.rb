module PathCoverage
  module Kinds
    # The hooks every kind has, each as most kinds need it; a
    # kind extends Base and defines its own in place of any.
    module Base
      # The ways a decision of this kind as a whole can be evaluated:
      # as it can be nested in another.
      def root_ways(node, fixed)
        ways(node, fixed)
      end

      # Whether its leaves, nested in a decision, need calls of their
      # own in place of record calls; false for most.
      def own_calls?
        false
      end

      # The inserts for a decision of this kind: its leaves' records,
      # and its leave around them.
      def decision_inserts(decision, condition)
        Rewriter.record_inserts(decision, condition) +
          Rewriter.trail_inserts(decision, condition)
      end

      # What a decision of this kind's leave call wraps: the whole of
      # it, for most.
      def trailed(condition)
        condition
      end

      # Its node in a decision's tree, each leaf taking the next index
      # of leaves: its operands' nodes, then its arms', if any.
      def node(source, condition, outcomes, leaves)
        built = [outcomes, leaves]
        operands = DecisionTree.operands_of(source, condition, *built)
        DecisionTree.arms(source, condition, operands, *built)
      end

      # The nodes its node stands for among its siblings' in a
      # decision's tree on a file's page: itself, for most.
      def unfold(node)
        [node]
      end

      # The inserts, besides its leaves' calls, for one nested in
      # a decision at its at-th leaf: none for most.
      def inserts(_decision, _inner, _at, _commands)
        []
      end

      # nodes, the tree nodes of condition's operands, with any
      # texts that repeat others cut: none for most.
      def texted(_source, _condition, nodes)
        nodes
      end

      # The text a decision of this kind opens and closes with, as
      # [opening, closing], eg ['{', '}'] for a block's braces.
      # Most kinds have none, so ['', ''].
      def brackets(_source, _decision)
        ['', '']
      end

      # Its operands' rows in a decision's tree on a file's page, nil
      # for most, whose operands branch from its operator.
      def rows(_condition, _indent)
        nil
      end
    end
  end
end
