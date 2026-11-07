require 'prism'
require_relative 'condition'

module PathCoverage
  # The leaves of a card whose outcomes cannot differ within one
  # call: each a read of a local variable that its method never
  # writes, eg a parameter, where the leaf's outcome is the
  # variable's truthiness. Every such read in a call has the same
  # outcome, so a way needing two outcomes of it is no way.
  module StableLeaves
    # The operators whose leaf operands' outcomes are their
    # truthiness. A when's leaf is whether its pattern matched, a
    # &. receiver's whether it was nil, false included in not nil,
    # and a block method's leaves count items or answers.
    TRUTHY = (%w[&& and || or] + CHOICES).freeze

    # The calls through which code can reach a method's locals
    # and rewrite them out of its sight: a binding, a string eval,
    # or any call by name, which could be either.
    REWRITERS = %i[
      binding eval instance_eval class_eval module_eval
      send __send__ public_send method
    ].freeze

    # Example: { 32...33 => :a, 54...55 => :a } for def f(a),
    # return 0 if a, then a ? 1 : 2.
    # { leaf byte range => local name } for each truthy leaf of
    # the decisions of rows, a card's in source, decisions being
    # { decision => Condition }, that reads, outside any block, a
    # local its def never writes, for each name two or more such
    # leaves read; none for a card in no def, or one whose def
    # calls any of REWRITERS.
    def self.of(source, decisions, rows)
      conditions = decisions.values_at(*rows.map(&:decision).compact)
      ranges = conditions.flat_map { truthy_leaves(_1) }
      return {} if ranges.empty?

      method = def_of(source, ranges.first)
      return {} if method.nil?

      shared(read_in(method).slice(*ranges))
    end

    # The leaves of condition, a leaf a byte range, whose outcome
    # is their truthiness, its nested conditions' included.
    def self.truthy_leaves(condition)
      operands = condition.operands
      own = TRUTHY.include?(condition.operator) ? operands : []
      own.grep(Range) + operands.flat_map { inner_leaves(_1) }
    end

    # The truthy leaves of operand, a leaf, a Condition or an Arm:
    # none for a leaf, which its condition counts, or a plain arm.
    def self.inner_leaves(operand)
      case operand
      when Condition then truthy_leaves(operand)
      when Arm then operand.body ? truthy_leaves(operand.body) : []
      else []
      end
    end

    # The innermost def in source holding the bytes range, nil
    # when none does.
    def self.def_of(source, range)
      defs = defs_in(Prism.parse(source).value)
      holding = defs.select do |node|
        loc = node.location
        (loc.start_offset...loc.end_offset).cover?(range)
      end
      holding.min_by { _1.location.length }
    end

    # Every def node in node, node itself included.
    def self.defs_in(node)
      own = node.type == :def_node ? [node] : []
      own + node.compact_child_nodes.flat_map { defs_in(_1) }
    end

    # { read byte range => local name } of each read in the def
    # node method, outside any block, of a local it never writes;
    # none when it calls any of REWRITERS.
    def self.read_in(method)
      reads = Reads.new
      reads.visit_child_nodes(method)
      return {} if reads.rewrites

      written = reads.written
      reads.reads.each_with_object({}) do |(range, name), kept|
        kept[range] = name unless written.include?(name)
      end
    end

    # The entries of named, { range => name }, whose name two or
    # more of them share.
    def self.shared(named)
      counts = named.values.tally
      named.each_with_object({}) do |(range, name), shared|
        shared[range] = name if counts[name] > 1
      end
    end

    # Notes, in a def's body, each read of a local outside any
    # block, def or lambda, where a local of the same name may be
    # another variable; each local written anywhere; and whether
    # any of REWRITERS is called.
    class Reads < Prism::Visitor
      # Starts outside any block, having noted nothing.
      def initialize
        @reads = {}
        @written = []
        @rewrites = false
        @depth = 0
        super
      end

      # { byte range => name } of each read noted; the names of
      # the locals written; and true when a rewriter is called.
      attr_reader :reads, :written, :rewrites

      # Notes a read, outside any block.
      def visit_local_variable_read_node(node)
        loc = node.location
        range = loc.start_offset...loc.end_offset
        @reads[range] = node.name if @depth.zero?
        super
      end

      # Notes the name of a write of a local, eg a = 1, a += 1, a
      # ||= 1, or a target, eg in a, b = 1, 2 or rescue => a.
      def visit_written(node)
        @written << node.name
        visit_child_nodes(node)
      end

      %i[
        local_variable_write_node local_variable_operator_write_node
        local_variable_or_write_node local_variable_and_write_node
        local_variable_target_node
      ].each do |type|
        alias_method :"visit_#{type}", :visit_written
      end

      # Notes a call of a rewriter.
      def visit_call_node(node)
        @rewrites = true if REWRITERS.include?(node.name)
        super
      end

      # Visits a block, a lambda or a def a level deeper, so its
      # reads are not noted.
      def visit_inner(node)
        @depth += 1
        visit_child_nodes(node)
        @depth -= 1
      end

      %i[block_node lambda_node def_node].each do |type|
        alias_method :"visit_#{type}", :visit_inner
      end
    end
  end
end
