require_relative 'base'
require_relative 'choice'

module PathCoverage
  module Kinds
    # A ||= or &&= write, which decides whether its right side
    # runs as an unless or an if decides its arm: its target is
    # its predicate, its right side its then arm, so its ways and
    # value are a choice's. Its target is never wrapped, so never
    # read again.
    module Write
      extend Base
      extend Arms

      OPERATORS = WRITES

      # Its target needs no record call, and its right side a
      # written_at call.
      def self.own_calls?
        true
      end

      # { target range => nil }: its target is never read, so
      # never wrapped.
      def self.calls(_decision, inner, _leaves)
        { inner.operands.first => nil }
      end

      # A write, its target the decision's at-th leaf: its right side
      # in a written_at call, which notes the target's outcome when
      # it runs, and the whole of it in a settle call, which notes
      # the other when it does not. A right side among commands,
      # eg a command call, is parenthesised. Eg x ||= v becomes,
      # in effect, settle(decision, at, true,
      # x ||= written_at(decision, at, false, v)).
      def self.inserts(decision, inner, at, commands)
        _target, arm = inner.operands
        ran = THEN_ON[inner.operator]
        name = decision.inspect
        written = "PathCoverage.written_at(#{name}, #{at}, #{ran}, "
        settle = "PathCoverage.settle(#{name}, #{at}, #{!ran}, "
        command = commands.include?(arm.extent)
        Rewriter.wrap(settle, inner.extent, false, :kind) +
          Rewriter.wrap(written, arm.extent, command, :leaf)
      end
    end
  end
end
