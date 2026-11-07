require 'prism'
require_relative 'condition'
require_relative 'leaving'
require_relative 'manifest_blocks'
require_relative 'manifest_case'
require_relative 'manifest_chains'
require_relative 'manifest_choices'
require_relative 'manifest_folding'
require_relative 'manifest_ignoring'
require_relative 'manifest_writes'
require_relative 'decision'

module PathCoverage
  # Finds every condition decision in source without running it: each
  # outermost &&, ||, and or or, each ternary, if, unless and case
  # with a subject, with the conditions nested in it.
  module Manifest
    # { decision => Condition } for each decision in source, none of
    # them named by an operator in ignored; a call to a method
    # named in present, as a &.'s receiver, is never nil, and a
    # call to one named in nonempty, eg any?, is true exactly
    # when its receiver has items.
    def self.decisions(source, path, ignored = [], present = [],
                       nonempty = [])
      collector = ConditionSites.new(path, ignored,
                                     [present, nonempty])
      Prism.parse(source).value.accept(collector)
      collector.decisions
    end

    # The source and decisions of the covered file at full_path.
    def self.parse(full_path, config)
      source = File.read(full_path)
      path = config.relative(full_path)
      treated = %w[present nonempty].map { config.treated(_1, path) }
      ignored = config.ignored
      { source:,
        decisions: decisions(source, path, ignored, *treated) }
    end

    # True for an expression that is no bare argument, so a
    # rewrite wrapping it in another call must parenthesise it: a
    # command call, an and or an or, or a modifier, eg x unless y.
    def self.bare_less?(node)
      return true if command?(node) || modifier?(node)

      %i[and_node or_node].include?(node.type) &&
        %w[and or].include?(node.operator)
    end

    # True for a call to a named method with arguments and no
    # parentheses, eg `id.include? 'N'`, but not `id.size == 6`.
    def self.command?(node)
      node.type == :call_node && node.arguments &&
        node.opening_loc.nil? && node.name.match?(/\A[a-z_]/i)
    end

    # True for a modifier if, unless or rescue, eg x if y: one
    # with no end keyword, a ternary being no modifier.
    def self.modifier?(node)
      case node.type
      when :rescue_modifier_node then true
      when :unless_node then node.end_keyword_loc.nil?
      when :if_node
        !node.if_keyword_loc.nil? && node.end_keyword_loc.nil?
      else false
      end
    end

    # Literals and lambdas, whose value is truthy by their form;
    # a constant is not among them, as it can hold nil or false.
    TRUTHY_TYPES = %i[
      string_node integer_node symbol_node array_node hash_node
      true_node lambda_node
    ].freeze
    FALSY_TYPES = %i[nil_node false_node].freeze

    # Ruby raises TypeError on assigning nil or false to these.
    TRUTHY_GLOBALS = %i[$stdout $stderr].freeze

    # The one outcome a leaf can have, eg :truthy for `Clock.new`
    # or a literal, :falsy for `nil`; nil for a leaf that can
    # have either.
    def self.fixed_outcome(node)
      return :falsy if FALSY_TYPES.include?(node.type)

      :truthy if truthy_only?(node)
    end

    # True for a leaf that can never be falsy.
    def self.truthy_only?(node)
      TRUTHY_TYPES.include?(node.type) || new_call?(node) ||
        truthy_global?(node)
    end

    # True for a call to new, eg `Clock.new`.
    def self.new_call?(node)
      node.type == :call_node && node.name == :new
    end

    # True for $stdout or $stderr, which can never be falsy.
    def self.truthy_global?(node)
      node.type == :global_variable_read_node &&
        TRUTHY_GLOBALS.include?(node.name)
    end

    # Collects each decision and its Condition.
    class ConditionSites < Prism::Visitor
      include ManifestBlocks
      include ManifestCase
      include ManifestChains
      include ManifestChoices
      include ManifestFolding
      include ManifestIgnoring
      include ManifestWrites

      # Starts with no decisions found, to find none named by an
      # operator in ignored, and to take a call to a method named
      # in present as never nil, and to one in nonempty as true
      # exactly when its receiver has items.
      def initialize(path, ignored, (present, nonempty))
        @path = path
        @ignored = ignored
        @present = present
        @nonempty = nonempty
        @decisions = {}
        @notes = nil
        @inner = nil
        super()
      end

      # The decisions found so far.
      attr_reader :decisions

      OPERATOR_TYPES = %i[and_node or_node].freeze

      # Notes an && or and decision.
      def visit_and_node(node)
        add_decision(node)
      end

      # Notes an || or or decision.
      def visit_or_node(node)
        add_decision(node)
      end

      # Notes a ternary or an if decision, a modifier if included,
      # its arms included.
      def visit_if_node(node)
        add_decision(node)
      end

      # Notes an unless decision, a modifier unless included, its
      # arms included.
      def visit_unless_node(node)
        add_decision(node)
      end

      # Notes a case decision, when its paths can be seen; any other
      # case is no decision, though a condition inside it may be.
      def visit_case_node(node)
        return super unless case_decision?(node)

        add_decision(node)
      end

      # Notes a &. chain as a decision, or a block method's call, when
      # its block's every call can be seen; any other call is no
      # decision, though a condition inside it may be.
      def visit_call_node(node)
        return add_decision(node) if safe_chain?(node)
        return super unless block_decision?(node)

        add_decision(node)
      end

      # Notes node as a decision, named where it starts: an if or an
      # unless at its keyword. It claims its place first, so a
      # decision found inside one of its leaves or arms follows it.
      # While a leaf is being visited, any decision is collected as
      # part of that leaf instead, as it is part of one expression.
      def add_decision(node)
        return visit_child_nodes(node) if ignored?(node)
        return @inner << nested_condition_of(node) if @inner

        decision = Decision.at(@path, decision_loc(node))
        @decisions[decision] = nil
        outer = @notes
        @notes = { commands: [], fixed: {} }
        condition = scoped { condition_of(node) }
        @decisions[decision] = condition.with(**@notes)
        @notes = outer
      end

      # node as a Condition, operands and all, named by its
      # operator as written; a ternary is named ?:, an if if and
      # an unless unless, their operands a predicate and arms; a
      # case case, its operands its arms; a write ||= or &&=, its
      # operands its target and its right side; a &. chain &., its
      # operands its receivers.
      def condition_of(node)
        return write_condition(node) if write?(node)
        return choice_of(node) if CHOICE_TYPES.include?(node.type)
        return case_condition(node) if node.type == :case_node
        return call_condition(node) if node.type == :call_node

        Condition.new(
          operator: node.operator, operands: operands_of(node),
          extent: extent_of(node)
        )
      end

      # node's operands: a chain of the same operator flattened
      # into one list, the other operator nested as a Condition,
      # as is a &. chain, its value its last leaf, an operand that
      # leaves the method an Arm, eg return t in x or return t,
      # anything else a leaf's byte range.
      def operands_of(node)
        [node.left, node.right].flat_map { operands_in(_1, node) }
      end

      # The operands written, one side of node, stands for, as
      # operands_of gives them.
      def operands_in(written, node)
        operand = grouped(written)
        return [leaf(operand)] if ignored?(operand)
        return [Leaving.arm(operand)] if Leaving.word(operand)
        return operands_of(operand) if operand.type == node.type
        return [condition_of(operand)] if operator?(operand)
        if safe_chain?(operand)
          return [chain_condition(operand, value: true)]
        end

        [leaf(operand)]
      end

      # The byte range of node as written.
      def extent_of(node)
        loc = node.location
        loc.start_offset...loc.end_offset
      end

      # True for an &&, ||, and or or node.
      def operator?(node)
        OPERATOR_TYPES.include?(node.type)
      end

      # The byte range of a leaf operand, noted among its decision's
      # commands and fixed leaves where it is one; or, when decisions
      # that fold are found inside it, the leaf with them nested.
      def leaf(operand)
        inner = leaf_decisions(operand)
        loc = operand.location
        range = loc.start_offset...loc.end_offset
        @notes[:commands] << range if Manifest.bare_less?(operand)
        outcome = Manifest.fixed_outcome(operand) ||
                  given_outcome(operand)
        @notes[:fixed][range] = outcome if outcome
        nonempty = nonempty_call?(operand, inner)
        contained(inner, range, nonempty:)
      end

      # The one statement inside a parenthesised operand, or the
      # operand itself.
      def grouped(operand)
        return operand unless operand.type == :parentheses_node

        body = operand.body
        statements = body ? body.body : []
        statements.size == 1 ? statements.first : operand
      end
    end
  end
end
