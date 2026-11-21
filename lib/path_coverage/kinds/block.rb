require_relative 'base'

module PathCoverage
  module Kinds
    # A block method's call, eg ids.any? { |id| id.odd? }: its
    # block's answers, its value following from them. Its
    # receiver's leaf has no outcome, as how many items the block
    # was called with is a loop's question. Nothing else is
    # evaluated, eg ids.size.
    module Block
      extend Base

      OPERATORS = BLOCK_PATHS.keys.freeze

      # A value that holds whatever the path, eg select's array.
      ALWAYS = ->(*) { true }

      # nil, nothing found, when its last answer was false; else
      # the item found, which may itself be nil, so nil, as no
      # path can tell.
      FOUND = ->(answer) { answer ? nil : false }

      # Its last answer, as the value of any?, all? and
      # find_index.
      LAST = ->(answer) { answer }

      # A block method's value from its block's last answer; nil
      # when the path cannot tell.
      VALUES = {
        'any?' => LAST, 'all?' => LAST, 'find_index' => LAST,
        'none?' => lambda(&:!),
        'detect' => FOUND,
        'find' => FOUND,
        'take_while' => ALWAYS,
        **EVERY_ITEM.to_h { |name| [name, ALWAYS] }
      }.freeze

      # Whether select's result has items: whether any answer
      # was true.
      KEPT = ->(answers) { answers != ANSWERS[1] }

      # Whether a block method's result has items, from its
      # block's answers, eg select keeps an item when any answer
      # was true; nil when its path cannot tell, eg take_while's
      # last answer false, which may or may not be its first.
      HAS_ITEMS = {
        'select' => KEPT, 'filter' => KEPT, 'filter_map' => KEPT,
        'reject' => ->(answers) { answers != ANSWERS[0] },
        'partition' => ALWAYS,
        'take_while' => ->(answer) { answer || nil }
      }.freeze

      # Whether decision's result has items on the path that took
      # outcomes; nil when its kind cannot tell, eg for a decision
      # that is no block method's call.
      def self.items?(decision, outcomes)
        _receiver, body = decision.operands
        rule = HAS_ITEMS[decision.operator]
        rule&.call(outcomes[body])
      end

      # The ways node can be evaluated, fixed by its shape, its
      # value following from each.
      def self.ways(node, _fixed)
        receiver, body = node.operands
        BLOCK_PATHS[node.operator].map do |items, answer|
          value = path_value(node.operator, answer)
          [{ receiver => items, body => answer }, value]
        end
      end

      # Its value on a path with its block's last answer, eg
      # false for any? with false, and always truthy for select,
      # which gives an array; nil for find with a last answer
      # true, whose value no path can tell.
      def self.path_value(operator, answer)
        VALUES[operator].call(answer)
      end

      # Its value in each column, from its block's answer there;
      # nil where it was not reached.
      def self.value(operator, operands)
        _receiver, body = operands
        body[:cells].map do |answer|
          answer.nil? ? nil : path_value(operator, answer)
        end
      end

      # Its block's opening and closing in source, ['{', '}'] or
      # ['do', 'end']: the opening between its receiver and its
      # block's expression, the closing after that expression.
      def self.brackets(source, decision)
        receiver, body = decision.operands
        between = source.byteslice(receiver.end...body.begin)
        closing = source.byteslice(body.end...decision.extent.end)
        [between[/\{|\bdo\b/], closing.strip]
      end

      # Its receiver needs no record call, and its block's
      # expression an item_at or answer_at call.
      def self.own_calls?
        true
      end

      # The calls for its leaves: none for its receiver, whose
      # leaf notes the items its block was called with, and an
      # item_at call, noting its last answer, or for a method that
      # calls it with every item an answer_at call, noting every
      # answer, for its block's expression.
      def self.calls(decision, inner, leaves)
        receiver, body = inner.operands
        at = leaves.index(receiver)
        every = EVERY_ITEM.include?(inner.operator)
        noter = every ? 'answer_at' : 'item_at'
        opening = "PathCoverage.#{noter}(#{decision.inspect}, #{at}, "
        { receiver => nil, body => opening }
      end

      # Its call wrapped whole, its receiver the decision's at-th
      # leaf, so its items are begun before it runs and counted
      # after.
      def self.inserts(decision, inner, at, _commands)
        name = decision.inspect
        begun = "PathCoverage.begin_items(#{name}, #{at})"
        call = "PathCoverage.end_items(#{name}, #{at}, #{begun}, "
        Rewriter.wrap(call, inner.extent, false, :kind)
      end
    end
  end
end
