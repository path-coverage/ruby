require_relative 'condition'
require_relative 'kinds'
require_relative 'rewriter_nested'

module PathCoverage
  # Instruments source text so that each leaf operand records its
  # outcome when the code runs. It inserts text at the byte
  # ranges the manifest found, and never parses.
  module Rewriter
    # Returns source with each operand in decisions wrapped in a
    # record call, each decision as a whole in a leave call that
    # enters it first, and each statement in reaches, { name =>
    # offset }, after a reach call that counts its runs. Only
    # text is inserted, never a newline, so backtrace line
    # numbers still match the file on disk.
    def self.rewrite(source, decisions, reaches = {})
      inserts = decisions.flat_map do |decision, condition|
        decision_inserts(decision, condition)
      end
      apply(source.dup, inserts + reach_inserts(reaches))
    end

    # Example: { "k.rb:2:2" => 18 } puts a reach call at 18.
    # The inserts that put a reach call, a statement of its
    # own, before each statement in reaches, outside all else
    # there. A statement reached by
    # its byte range, eg an endless def's body, is wrapped in
    # parentheses with its call, being one expression.
    def self.reach_inserts(reaches)
      rank = [Float::INFINITY, LAYERS.index(:reach)]
      reaches.flat_map do |name, at|
        call = "PathCoverage.reach(#{name.inspect}); "
        next [[at, call, rank]] unless at.is_a?(Range)

        [[at.begin, "(#{call}", rank], [at.end, ')', rank, :close]]
      end
    end

    # The inserts for one decision, as its kind gives them, eg its
    # leaves' records and its leave; a block method's call or a
    # write is noted as if nested at leaf 0.
    def self.decision_inserts(decision, condition)
      Kinds.of(condition.operator).decision_inserts(decision,
                                                    condition)
    end

    # The inserts that wrap each of decision's leaves in a record
    # call, innermost of all; a leaf of a nested decision that needs
    # a call of its own, eg a &. chain's, in the call
    # RewriterNested gives it, or in none, and that decision's own
    # inserts too.
    def self.record_inserts(decision, condition)
      nested = RewriterNested.calls(decision, condition)
      leaves = condition.leaves
      records = leaves.each_with_index.flat_map do |range, i|
        call = nested.fetch(range) { record_call(decision, i) }
        next [] unless call

        wrap(call, range, condition.commands.include?(range), :leaf)
      end
      records + RewriterNested.inserts(decision, condition)
    end

    WORD_OPERATORS = %w[and or].freeze

    # The inserts that wrap decision as a whole in a leave call,
    # outside its leaves' record calls, whose first argument
    # enters the decision before any leaf runs, so each evaluation
    # fills in a trail of its own. An and or or is held in
    # parentheses, being, like a command call, no bare argument.
    def self.trail_inserts(decision, condition)
      enter = "PathCoverage.enter(#{decision.inspect}, " \
              "#{condition.leaves.size})"
      call = "PathCoverage.leave(#{enter}, "
      wrapped = Kinds.of(condition.operator).trailed(condition)
      nested = wrapped.is_a?(Condition)
      word = nested && WORD_OPERATORS.include?(wrapped.operator)
      wrap(call, nested ? wrapped.extent : wrapped, word, :decision)
    end

    # The opening of the record call around operand index of
    # the decision.
    def self.record_call(decision, index)
      "PathCoverage.record(#{decision.inspect}, #{index}, "
    end

    # The layers of inserts, innermost first, that break a tie
    # between inserts wrapping the same range: a leaf's call, a
    # nested kind's call around its whole, eg end_items, a decision's
    # leave, and a statement's reach.
    LAYERS = %i[leaf kind decision reach].freeze

    # The two inserts that wrap the code at range in call. Their
    # order, [size, rank], nests them among inserts at the same
    # offset: the longer range outside, the rank of layer in
    # LAYERS breaking a tie. A command call is parenthesised, as
    # it is no bare argument; nothing else is, since parentheses
    # make a statement, which gives its line a line-coverage
    # count of its own.
    def self.wrap(call, range, command, layer)
      open, close = command ? ['(', '))'] : ['', ')']
      order = [range.size, LAYERS.index(layer)]
      [
        [range.begin, call + open, order],
        [range.end, close, order, :close]
      ]
    end

    # Splices each [offset, text, order] insert into source,
    # last offset first so earlier offsets stay valid; a closing
    # insert is marked :close. Text spliced in later at an
    # offset lands before text already there, so at one offset
    # opening inserts go in lowest order first, leaving the
    # highest outermost, then closing ones highest order first,
    # so the innermost call closes first. Eg a ternary whose
    # predicate is a leaf: the decision's leave, wrapping the whole
    # ternary, opens outside the record wrapping its predicate.
    def self.apply(source, inserts)
      sorted = inserts.sort_by do |offset, _, order, close|
        size, rank = order
        close ? [-offset, 1, -size, -rank] : [-offset, 0, size, rank]
      end
      sorted.each do |offset, text, _|
        source.bytesplice(offset, 0, text)
      end
      source
    end
  end
end
