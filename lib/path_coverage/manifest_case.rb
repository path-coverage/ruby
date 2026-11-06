require_relative 'condition'

module PathCoverage
  # The part of the manifest's visitor that builds a case decision,
  # named case: its arms are its whens, each holding a when
  # condition of its patterns, and its else. It relies on its
  # includer's extent_of and statement_arm.
  module ManifestCase
    # True for a case whose paths can be seen: one with a
    # subject, as each pattern is then matched against it, and
    # no splat among its patterns, whose items cannot each be
    # stood in for.
    def case_decision?(node)
      return false if node.predicate.nil?

      patterns = node.conditions.flat_map(&:conditions)
      !patterns.map(&:type).include?(:splat_node)
    end

    # A case as a Condition, its extent its case keyword to the
    # end of its subject, as its arms are statements.
    def case_condition(node)
      node.predicate.accept(self)
      whens = node.conditions.map { |clause| when_arm(clause) }
      start = node.case_keyword_loc.start_offset
      Condition.new(
        operator: 'case',
        operands: [*whens, *case_else(node.else_clause)],
        extent: start...node.predicate.location.end_offset
      )
    end

    # One when as an arm, its body a when condition whose leaves
    # are its patterns' byte ranges. A pattern is matched, not
    # tested for truth, so none is ever fixed.
    def when_arm(clause)
      patterns = clause.conditions.map do |pattern|
        pattern.accept(self)
        extent_of(pattern)
      end
      body = Condition.new(
        operator: 'when', operands: patterns,
        extent: patterns.first.begin...patterns.last.end
      )
      statement_arm(:when, clause.statements).with(body:)
    end

    # A case's else arm, none when it has no else.
    def case_else(clause)
      clause ? [statement_arm(:else, clause.statements)] : []
    end
  end
end
