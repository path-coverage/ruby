require_relative 'condition'

module PathCoverage
  # Whether code leaves the method where it stands, decided once,
  # from Prism's nodes, for every part of the gem that asks.
  module Leaving
    # The methods whose call, with no receiver, leaves the method:
    # raise, fail, its other name, and throw, for its catch.
    CALLS = %i[raise fail throw].freeze

    # 'return' for a return, the method's name for a call of one of
    # CALLS with no receiver, eg 'fail'; nil for a statement that
    # does not leave the method.
    def self.word(statement)
      return 'return' if statement.type == :return_node

      statement.name.to_s if leaving_call?(statement)
    end

    # The arm a statement that leaves the method is as an operand,
    # eg return t in x or return t: run when the operand before it
    # gives the outcome its operator goes on with, never a value,
    # so never a leaf.
    def self.arm(statement)
      loc = statement.location
      Arm.new(kind: :then, extent: loc.start_offset...loc.end_offset,
              body: nil, leaves: word(statement))
    end

    # The word of the first of an arm's statements that leaves the
    # method, statements its code; nil for an arm with no
    # statements or none that leaves.
    def self.of(statements)
      statements && statements.body.map { word(_1) }.compact.first
    end

    # True when statement is a call of one of CALLS with no
    # receiver.
    def self.leaving_call?(statement)
      statement.type == :call_node && statement.receiver.nil? &&
        CALLS.include?(statement.name)
    end
  end
end
