module PathCoverage
  # The loops in a method's Prism tree: its blocks, lambdas,
  # whiles, untils and fors, each run 0 or more times, and their
  # bodies, as MethodLoops and LoopForks take them.
  module LoopNodes
    # The types of node that are loops written with a keyword,
    # their body their statements.
    KEYWORDS = %i[while_node until_node for_node].freeze

    # The types of node that are loops.
    LOOPS = [:block_node, :lambda_node, *KEYWORDS].freeze

    # Every def under node, outermost first.
    def self.defs(node)
      found = node.type == :def_node ? [node] : []
      found + node.compact_child_nodes.flat_map { defs(_1) }
    end

    # Every loop under node, in the order they start, but none
    # inside a def under it, whose loops are its own.
    def self.loops_in(node)
      return [] if node.nil? || node.type == :def_node

      own = LOOPS.include?(node.type) ? [node] : []
      own + node.compact_child_nodes.flat_map { loops_in(_1) }
    end

    # The body of loop: a block's or lambda's body, a keyword
    # loop's statements; nil for an empty one.
    def self.body_of(loop)
      KEYWORDS.include?(loop.type) ? loop.statements : loop.body
    end

    # True for a keyword loop written after its body, eg x += 1
    # while x < 9, where a call put first in its body would run
    # once, not each pass, so none goes there.
    def self.modifier?(loop)
      return false unless KEYWORDS.include?(loop.type)

      body = loop.statements.location
      loop.keyword_loc.start_offset > body.start_offset
    end

    # The first statement of a loop's body, a do ... rescue ... end
    # block's being its first before the rescue; nil when it has
    # none there, its statements all in its rescue, which run only
    # once a statement raises, so there is no pass to note.
    def self.first_statement(body)
      return body.body.first unless body.type == :begin_node
      return if body.statements.nil?

      body.statements.body.first
    end
  end
end
