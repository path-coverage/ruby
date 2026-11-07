require_relative 'condition'

module PathCoverage
  # The part of the manifest's visitor that builds the decisions of
  # ||= and &&= writes, eg @clock ||= Clock.new. It relies on
  # its includer's add_decision and extent_of.
  module ManifestWrites
    # Every node type of a ||= or &&= write, by its target: a
    # variable of each kind, a constant, a constant path, an
    # attribute, eg self.size, and an index, eg store[key].
    WRITE_TYPES = %w[
      local_variable instance_variable class_variable
      global_variable constant constant_path call index
    ].flat_map do |target|
      %W[#{target}_or_write_node #{target}_and_write_node]
    end.map(&:to_sym).freeze

    # Notes each kind of write as a decision, eg
    # visit_index_or_write_node for store[key] ||= 0.
    WRITE_TYPES.each do |type|
      define_method(:"visit_#{type}") do |node|
        write?(node) ? add_decision(node) : visit_child_nodes(node)
      end
    end

    # True for a ||= or &&= write that is a decision: any but one
    # through &., eg box&.size ||= 3, which a nil box skips whole,
    # its target never looked at, so neither of its paths taken.
    def write?(node)
      WRITE_TYPES.include?(node.type) && !safe_write?(node)
    end

    # True for a write through &., eg box&.size ||= 3.
    def safe_write?(node)
      node.respond_to?(:safe_navigation?) && node.safe_navigation?
    end

    # A write as a Condition, named by its operator: its one leaf
    # its target, then its right side as an arm, taken when the
    # target is false for ||=, true for &&=. The target is a
    # leaf the rewriter never reads again, as reading it could
    # call a method twice; its outcome follows from whether the
    # arm ran. Any decision inside the write, eg in an index or on
    # the right side, is a decision of its own. A right side that is
    # no bare argument, eg a command call, is noted among the
    # decision's commands, to be parenthesised.
    def write_condition(node)
      visit_child_nodes(node)
      value = extent_of(node.value)
      @notes[:commands] << value if Manifest.bare_less?(node.value)
      arm = Arm.new(kind: :then, extent: value, body: nil,
                    leaves: nil)
      Condition.new(
        operator: node.operator, operands: [target_of(node), arm],
        extent: extent_of(node)
      )
    end

    # The byte range of a write's target: from its start to its
    # operator, less any space between, eg `store[key]`.
    def target_of(node)
      start = node.location.start_offset
      before = node.operator_loc.start_offset - start
      text = node.location.slice.byteslice(0, before)
      start...(start + text.rstrip.bytesize)
    end
  end
end
