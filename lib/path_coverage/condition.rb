module PathCoverage
  # The operators whose predicate picks an arm.
  CHOICES = %w[?: if unless].freeze

  # An arm whose code leaves the method, by its code's start: a
  # return or a raise, captured.
  LEAVES = /\A(return|raise)\b/

  # The operator of a safe-navigation chain, eg user&.account.
  SAFE = '&.'.freeze

  # The operator of a leaf with decisions inside it, eg
  # ids.select { |i| i.odd? }.any? as an operand of an &&: its
  # operands are those decisions' Conditions, then the leaf's own byte
  # range, whose outcome is the leaf's value.
  CONTAINS = 'contains'.freeze

  # A &. receiver's outcome: not nil, so the call is made, false
  # included, or nil, so the rest of the chain is skipped.
  PRESENCE = ['not nil', 'nil'].freeze

  # The writes whose target decides whether their right side
  # runs, as an unless or an if decides its arm: x ||= v runs v
  # when x is false, x &&= v when x is true.
  WRITES = %w[||= &&=].freeze

  # The predicate outcome on which each choice takes its then
  # arm: an unless's is false, as is a ||= write's.
  THEN_ON = Hash.new(true).merge('unless' => false, '||=' => false)
                .freeze

  # The methods that call their block an item at a time until
  # it decides, its last answer deciding the result.
  STOP_EARLY = %w[
    any? all? none? find detect find_index take_while
  ].freeze

  # How many items a block method's block was called with, as
  # its receiver's leaf outcome: none, one, or two or more.
  ITEMS = ['0 items', '1 item', '2+ items'].freeze

  # Every path a stop-early block method's call can take: how
  # many items its block was called with, and its last answer,
  # nil when it was never called.
  STOP_EARLY_PATHS = [
    [ITEMS[0], nil],
    [ITEMS[1], true], [ITEMS[1], false],
    [ITEMS[2], true], [ITEMS[2], false]
  ].freeze

  # The methods that call their block with every item.
  EVERY_ITEM = %w[
    select filter reject partition count filter_map
  ].freeze

  # A block's answers over every item it was called with.
  ANSWERS = ['all true', 'all false', 'both'].freeze

  # Every path an every-item block method's call can take: how
  # many items its block was called with, and its answers,
  # which can be both only with two or more items.
  EVERY_ITEM_PATHS = [
    [ITEMS[0], nil],
    [ITEMS[1], ANSWERS[0]], [ITEMS[1], ANSWERS[1]],
    [ITEMS[2], ANSWERS[0]], [ITEMS[2], ANSWERS[1]],
    [ITEMS[2], ANSWERS[2]]
  ].freeze

  # The block methods whose value follows from their path alone:
  # all but find and detect, whose found item may itself be nil.
  VALUED = [*STOP_EARLY - %w[find detect], *EVERY_ITEM].freeze

  # Every block method whose call is a decision, by its paths.
  BLOCK_PATHS = [
    *STOP_EARLY.map { |name| [name, STOP_EARLY_PATHS] },
    *EVERY_ITEM.map { |name| [name, EVERY_ITEM_PATHS] }
  ].to_h.freeze

  # One arm of a ternary, an if or an unless: kind is :then or
  # :else, extent its byte range, nil for an arm with no
  # statements, and body the Condition it is, when it is one,
  # else nil for a plain value or statements, which decide
  # nothing.
  Arm = Data.define(:kind, :extent, :body)

  # One decision's condition as the manifest found it: its operator
  # and its operands, each the byte range of a leaf or a nested
  # Condition. A decision's commands are the byte ranges of its
  # leaves that are command calls, eg `ok? id`; its fixed are
  # { byte range => :truthy } for leaves that can have that one
  # outcome only, eg `Clock.new`. Its extent is the byte range
  # of the whole condition as written, eg a ternary's from its
  # predicate to its else arm, which its leaves alone cannot
  # give.
  Condition = Data.define(
    :operator, :operands, :commands, :fixed, :extent
  ) do
    # A condition with no command-call or fixed leaves, and no
    # extent, by default.
    def initialize(
      operator:, operands:, commands: [], fixed: {}, extent: nil
    )
      super
    end

    # The byte range of every leaf operand, left to right, a
    # ternary's arms' after its predicate's; a leaf's index here
    # is the index it is recorded under.
    def leaves
      operands.flat_map do |operand|
        case operand
        when Condition then operand.leaves
        when Arm then arm_leaves(operand)
        else [operand]
        end
      end
    end

    # The leaves of arm's body, none for an arm whose body is no
    # condition.
    def arm_leaves(arm)
      body = arm.body
      body ? body.leaves : []
    end
  end
end
