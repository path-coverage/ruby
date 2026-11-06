require_relative 'condition'

module PathCoverage
  # The part of the manifest's visitor that builds the decision of a
  # call to a block method, one that calls its block an item at
  # a time, until it decides, eg any?, or for every item, eg
  # select: its leaves are its receiver, whose items the block
  # is called with, and its block's one expression, whose
  # answers decide. It relies on its includer's extent_of and
  # @notes.
  module ManifestBlocks
    # True for a call whose block's every call can be seen: to a
    # block method, on a receiver, with no arguments, which can
    # make it ignore its block, not by &., which skips it for
    # nil, and with a block of one expression that is a value,
    # so can be wrapped: not break, next or return.
    def block_decision?(node)
      return false unless BLOCK_PATHS.key?(node.name.to_s)

      plain_call?(node) && value?(block_expression(node.block))
    end

    # True for a call on a receiver, with no arguments. A call by
    # &. never gets here, as it is a decision of its own first.
    def plain_call?(node)
      !node.receiver.nil? && node.arguments.nil?
    end

    # True for a block's one expression that is a value, so can
    # be wrapped: nil, for no one expression, is not, nor is a
    # jump.
    def value?(body)
      !body.nil? && !JUMPS.include?(body.type)
    end

    # The expressions that leave a block, so are no value.
    JUMPS = %i[break_node next_node return_node].freeze

    # The one expression of block, nil for no block, a block
    # passed as an argument, or one of other than one expression.
    def block_expression(block)
      return nil unless block&.type == :block_node

      statements = block.body
      return nil unless statements&.type == :statements_node

      statements.body.size == 1 ? statements.body.first : nil
    end

    # A block method's call as a Condition, named by its method,
    # its extent the whole call. Its block's expression is noted
    # among the commands when it is no bare argument.
    def block_condition(node)
      node.receiver.accept(self)
      body = block_body(node.block)
      Condition.new(
        operator: node.name.to_s,
        operands: [extent_of(node.receiver), body],
        extent: extent_of(node)
      )
    end

    # The byte range of block's one expression, any decision in it
    # visited as one of its own, as the block runs once per item;
    # noted among the commands when it is no bare argument.
    def block_body(block)
      body = block_expression(block)
      scoped { body.accept(self) }
      range = extent_of(body)
      @notes[:commands] << range if bare_less?(body)
      range
    end

    # True for an expression that is no bare argument: a command
    # call, an and or an or, or a modifier, eg x unless y.
    def bare_less?(node)
      return true if Manifest.command?(node) || modifier?(node)

      %i[and_node or_node].include?(node.type) &&
        %w[and or].include?(node.operator)
    end

    # True for a modifier if, unless or rescue, eg x if y: one
    # with no end keyword, a ternary being no modifier.
    def modifier?(node)
      case node.type
      when :rescue_modifier_node then true
      when :unless_node then node.end_keyword_loc.nil?
      when :if_node
        !node.if_keyword_loc.nil? && node.end_keyword_loc.nil?
      else false
      end
    end
  end
end
