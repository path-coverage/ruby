require_relative 'condition'

module PathCoverage
  # Where in its source each part of a decision's tree is, as
  # [line, column, line, column], so a page can light the code
  # a fold row stands for.
  module DecisionLocations
    # simplecov:disable
    # SPIKE: tree with an at: of [line, column, line, column]
    # on it and on each of its operands: a leaf's from its byte
    # range, a condition's and an arm's from its extent, the
    # whole of it as written. Columns count characters, not
    # bytes. A node past the condition's operands, eg owner at
    # the end of user&.account&.owner, is kept as it is.
    def self.located(source, condition, tree)
      pairs = condition.operands.zip(tree[:operands])
      operands = pairs.map do |operand, node|
        located_operand(source, operand, node)
      end
      rest = tree[:operands].drop(pairs.size)
      tree.merge(at: at(source, condition.extent),
                 operands: operands + rest)
    end

    # SPIKE: the node of operand with its at:, as located gives
    # a condition's, an arm's or a leaf's.
    def self.located_operand(source, operand, node)
      case operand
      when Condition then located(source, operand, node)
      when Arm then located_arm(source, operand, node)
      else node.merge(at: at(source, operand))
      end
    end

    # An arm's node with its at:, nil for an arm with no
    # statements, and its body's tree located.
    def self.located_arm(source, arm, node)
      body = arm.body ? located(source, arm.body, node[:body]) : nil
      at = arm.extent ? at(source, arm.extent) : nil
      node.merge(at:, body:)
    end

    # [line, column, line, column] of the byte range in source.
    def self.at(source, range)
      [*position(source, range.begin), *position(source, range.end)]
    end

    # [line, column] of a byte offset in source.
    def self.position(source, offset)
      before = source.byteslice(0, offset)
      newline = before.rindex("\n")
      column = before.length - (newline ? newline + 1 : 0)
      [before.count("\n") + 1, column]
    end
    # simplecov:enable

    # [line, column, line, column] of condition's else keyword in
    # source, so hovering it can open condition's fold, as
    # hovering its if does; nil for one with no else, or one whose
    # else has no code, or a ?:, whose else is no keyword. The
    # keyword is what comes just before its arm's code, so an
    # elsif, or an else with a comment after it, has none.
    def self.else_at(source, condition)
      return nil if condition.operator == '?:'

      arm = condition.operands.grep(Arm).to_h { [_1.kind, _1] }[:else]
      extent = arm&.extent
      return nil unless extent

      start = source.b.byteslice(0, extent.begin) =~ /\belse\s*\z/
      return nil unless start

      at(source, start...(start + 4))
    end
  end
end
