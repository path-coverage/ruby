require 'prism'

module PathCoverage
  # The scope a top card is named for: the module or class its
  # lines are in, as a def names a method's card.
  module CardScopes
    # The kinds of node that are a top card's scope.
    HOLDERS = [Prism::ModuleNode, Prism::ClassNode].freeze

    # A lambda giving the scope of a line of source, as scope
    # gives it, its modules and classes found once.
    def self.of(source)
      holders = holders_in(Prism.parse(source).value)
      ->(line) { scope(holders, line) }
    end

    # Example: line 2, inside module Shop on lines 1 to 9, gives
    # Shop.
    # The name of the innermost of holders, modules and classes,
    # whose lines hold line, a top card's scope, as a def is a
    # method card's; file for a line in none.
    def self.scope(holders, line)
      holding = holders.select do |node|
        location = node.location
        (location.start_line..location.end_line).cover?(line)
      end
      holding.empty? ? 'file' : holding.last.name.to_s
    end

    # Every module and class node in the tree at node, each
    # before those nested in it.
    def self.holders_in(node)
      own = HOLDERS.include?(node.class) ? [node] : []
      own + node.compact_child_nodes.flat_map { holders_in(_1) }
    end
  end
end
