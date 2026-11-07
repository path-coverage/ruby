module PathCoverage
  # Whether code leaves the method where it stands, decided once,
  # from Prism's nodes, for every part of the gem that asks.
  module Leaving
    # 'return' for a return, 'raise' for a call of raise with no
    # receiver; nil for a statement that does not leave the method.
    def self.word(statement)
      return 'return' if statement.type == :return_node

      'raise' if raise?(statement)
    end

    # The word of an arm's first statement, statements its code; nil
    # for an arm with no statements or whose first does not leave.
    def self.of(statements)
      statements && word(statements.body.first)
    end

    # True when statement is a call of raise with no receiver.
    def self.raise?(statement)
      statement.type == :call_node && statement.receiver.nil? &&
        statement.name == :raise
    end
  end
end
