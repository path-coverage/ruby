require_relative 'condition'
require_relative 'leaving'

module PathCoverage
  # The part of the manifest's visitor that builds the decisions
  # whose predicate picks an arm: a ternary, named ?:, an if,
  # named if, and an unless, named unless. It relies on its
  # includer's condition_of, extent_of, grouped, leaf and
  # operator?.
  module ManifestChoices
    # The node types whose predicate picks an arm, a ternary
    # being an if_node with no if keyword.
    CHOICE_TYPES = %i[if_node unless_node].freeze

    # Where node's decision is named: a &. chain's start; a block
    # method's call at its method; a ternary at its ?, so it never
    # shares the name of a decision starting where it does, eg its
    # predicate; an if's or an unless's keyword, which a
    # modifier's statement comes before; anything else's own start.
    def decision_loc(node)
      return node.location if safe_chain?(node)
      return node.message_loc if node.type == :call_node
      return node.location unless CHOICE_TYPES.include?(node.type)
      return node.then_keyword_loc if ternary?(node)

      keyword_loc(node)
    end

    # The location of an if's or an unless's keyword.
    def keyword_loc(node)
      unless?(node) ? node.keyword_loc : node.if_keyword_loc
    end

    # True for an unless.
    def unless?(node)
      node.type == :unless_node
    end

    # A ternary, an if or an unless as a Condition.
    def choice_of(node)
      ternary?(node) ? ternary_condition(node) : if_condition(node)
    end

    # A ternary as a Condition, its extent the whole of it.
    def ternary_condition(node)
      Condition.new(
        operator: '?:', operands: ternary_of(node),
        extent: extent_of(node)
      )
    end

    # An if or an unless as a Condition, named by its keyword,
    # its extent its keyword to the end of its predicate, as its
    # arms are statements, not part of the expression.
    def if_condition(node)
      start = keyword_loc(node).start_offset
      Condition.new(
        operator: unless?(node) ? 'unless' : 'if',
        operands: if_of(node),
        extent: start...node.predicate.location.end_offset
      )
    end

    # An if's or an unless's predicate, then its then arm and,
    # when it has one, its else arm.
    def if_of(node)
      rest = unless?(node) ? node.else_clause : node.subsequent
      [
        predicate_of(node),
        statement_arm(:then, node.statements),
        *else_arm(rest)
      ]
    end

    # An if's arm, statements its code, which never folds into
    # the if's decision; as a new scope, any decision inside it
    # is a decision of its own. An arm with no statements has no
    # extent.
    def statement_arm(kind, statements)
      scoped { statements&.accept(self) }
      extent = statements ? extent_of(statements) : nil
      leaves = Leaving.of(statements)
      Arm.new(kind:, extent:, body: nil, leaves:)
    end

    # An if's else arm, from subsequent: an else's statements,
    # or an elsif, which is a decision of its own; none for none.
    def else_arm(subsequent)
      return [] if subsequent.nil?
      if subsequent.type == :else_node
        return [statement_arm(:else, subsequent.statements)]
      end

      scoped { subsequent.accept(self) }
      extent = extent_of(subsequent)
      [Arm.new(kind: :else, extent:, body: nil, leaves: nil)]
    end

    # A ternary's predicate, then its then and else arms.
    def ternary_of(node)
      [
        predicate_of(node),
        arm_of(:then, node.statements),
        arm_of(:else, node.subsequent.statements)
      ]
    end

    # One arm of a ternary, statements its code: a ternary, or a
    # block method's call whose value follows from its path, is a
    # decision of its own, as an if's arm holding an if is, so the arm
    # is plain; another condition folds in as its body, being part
    # of the one expression, as does a plain arm with decisions inside
    # it, its value its last leaf; a plain arm with none has no
    # body.
    def arm_of(kind, statements)
      written = grouped(statements.body.first)
      extent = extent_of(statements)
      body = if ternary?(written) || valued?(written)
               own_decision(statements)
             else
               arm_body(written, statements, extent)
             end
      Arm.new(kind:, extent:, body:, leaves: Leaving.of(statements))
    end

    # No body, for an arm, statements its code, whose one decision is
    # a decision of its own: visited in a new scope, so noted as one.
    def own_decision(statements)
      scoped { statements.accept(self) }
      nil
    end

    # The body of a ternary's arm, statements its code, written its
    # one expression, extent its byte range: the condition written
    # is, when it folds; else the decisions inside it, contained, nil
    # for none.
    def arm_body(written, statements, extent)
      return condition_of(written) if foldable?(written)

      inner = collected { statements.accept(self) }
      inner.empty? ? nil : contained(inner, extent)
    end

    # True for a condition that folds into a ternary's decision: an
    # &&, ||, and or or not ignored.
    def foldable?(node)
      operator?(node) && !ignored?(node)
    end

    # True for a ternary, an if with no if keyword.
    def ternary?(node)
      node.type == :if_node && node.if_keyword_loc.nil?
    end

    # A ternary's or an if's predicate as its operand: a &. chain
    # nested as a Condition, its value its last leaf; anything
    # else a leaf, an && or || among them, as a decision of its own,
    # as leaf_decisions has it.
    def predicate_of(node)
      predicate = grouped(node.predicate)
      return leaf(predicate) if ignored?(predicate)
      if safe_chain?(predicate)
        return chain_condition(predicate, value: true)
      end

      leaf(predicate)
    end
  end
end
