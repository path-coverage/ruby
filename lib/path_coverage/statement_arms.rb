module PathCoverage
  # The lists of statements a method's card has rows for: a def's
  # body, the arms of each decision in it whose arms are statements,
  # and the body of each block in it, as the card lays them out
  # flat. It relies on its includer's rows_in, decision? and
  # decision_name.
  module StatementArms
    # The nodes a statement's decisions are never looked for in: a
    # block's, a lambda's and a begin's statements are rows of
    # their own, after the statement holding them, and a def's
    # body runs only when it is called, its decisions rows of its own
    # card.
    UNSEEN = %i[block_node begin_node def_node lambda_node].freeze

    # Example: if/else for if a then 1 else 2 end.
    # operator, a decision node's, with /else after it when node is an
    # if or an unless with an else, so its row names both arms;
    # operator alone for any other, eg a ?:, whose arms are ? and :.
    def with_else(operator, node)
      return operator unless %w[if unless].include?(operator)

      clause = operator == 'if' ? node.subsequent : node.else_clause
      clause&.type == :else_node ? "#{operator}/else" : operator
    end

    # The tops of statements that end a path, leaving the method.
    LEAVING = %w[return raise].freeze

    # True for a row that shapes its method's paths: a decision, or a
    # return or a raise, which ends a path. Any other, eg x = 1,
    # runs exactly where what holds it does, so is no row.
    def shapes?(node)
      decision?(node) || LEAVING.include?(top_of(node))
    end

    # Where node, a def, is entered: its body's start, or, for an
    # endless def, whose body is one expression, its byte range,
    # to be wrapped; before its end for an empty body.
    def entry_at(node)
      body = node.body
      return node.end_keyword_loc.start_offset if body.nil?

      loc = body.location
      start = loc.start_offset
      node.equal_loc ? start...loc.end_offset : start
    end

    # Example: return a ? 1 : 2 if x gives the ?:.
    # The decisions inside decision that are decisions of their
    # own, in the order they are written: in its leaves, eg a
    # modifier if's arm or a &. call's receiver; not in its arms
    # of statements, nor in a body, which have rows of their own.
    # A decision is named where it starts, so a node starting
    # where a decision does, eg a ?:'s predicate, names that
    # decision: each is kept once, and decision itself not at
    # all. None for a top that is no decision, eg a def inside a
    # def, whose decisions are on its own card.
    def inner_decisions(decision)
      return [] unless decision?(decision)

      found = heads(decision).flat_map { decisions_within(_1) }
      named = found.to_h { [decision_name(_1), _1] }
      named.except(decision_name(decision)).values
    end

    # node when it is a decision, then each decision within it, in
    # order; none in a body or a def.
    def decisions_within(node)
      return [] if UNSEEN.include?(node.type)

      own = decision?(node) ? [node] : []
      own + heads(node).flat_map { decisions_within(_1) }
    end

    # Example: items.map { |i| i.price } gives the price row.
    # The rows of the bodies in statement: of each block's and
    # lambda's statements, a block method's included,
    # as its block's decisions are decisions of their own, and a reach
    # call before its one expression sits outside the
    # expression's own record call; and of each begin's parts.
    def body_rows(statement)
      bodies_in(statement).flat_map do |body|
        rows_in(statements_of(body))
      end
    end

    # The body of each block and lambda in node, run 0 or more
    # times, and each begin: none inside an arm of statements or
    # another body, whose rows are their own, nor in a def, whose
    # rows are its own card's.
    def bodies_in(node)
      case node.type
      when :def_node then []
      when :block_node, :lambda_node then [node.body]
      when :begin_node then [node]
      else heads(node).flat_map { bodies_in(_1) }
      end
    end

    # node's children outside its arms of statements: all of
    # them for a node with none, else its predicate, and a
    # case's patterns too.
    def heads(node)
      return node.compact_child_nodes if arms_of(node).empty?
      return [node.predicate] unless node.type == :case_node

      [node.predicate, *node.conditions.flat_map(&:conditions)]
    end

    # The statements of node's arms, then's before else's; none
    # when node has no arms of statements, as a modifier's arm,
    # and a ?:'s, are part of the decision's own expression.
    def arms_of(node)
      case node.type
      when :if_node then if_arms(node)
      when :unless_node then unless_arms(node)
      when :case_node then case_arms(node)
      else []
      end
    end

    # A case's arms' statements: each when's in turn, then its
    # else's.
    def case_arms(node)
      whens = node.conditions.flat_map do |clause|
        statements_of(clause.statements)
      end
      whens + else_arms(node.else_clause)
    end

    # An if's arms' statements, an elsif standing as a statement
    # of its if's else; none for a ?: or a modifier if.
    def if_arms(node)
      return [] if node.if_keyword_loc.nil? || then_first?(node)

      statements_of(node.statements) + else_arms(node.subsequent)
    end

    # An unless's arms' statements; none for a modifier unless.
    def unless_arms(node)
      return [] if then_first?(node)

      statements_of(node.statements) + else_arms(node.else_clause)
    end

    # True for an if or unless whose then arm is written before
    # its predicate: a modifier, eg x if y.
    def then_first?(node)
      statements = node.statements
      return false if statements.nil?

      predicate = node.predicate.location.start_offset
      statements.location.start_offset < predicate
    end

    # The statements of an if's else, an elsif as one of them,
    # none for none.
    def else_arms(node)
      return [node] if node&.type == :if_node

      clause_statements(node)
    end

    # The statements of clause, an else or an ensure; none for
    # none.
    def clause_statements(clause)
      clause ? statements_of(clause.statements) : []
    end

    # The top-level statements of a def's body, a block's, or an
    # arm's; with a rescue, those of each part in turn.
    def statements_of(body)
      return begun(body) if body&.type == :begin_node

      body ? body.body : []
    end

    # A begin's statements, then each rescue's, as each runs when
    # its exception is raised, its else's, run when none is, and
    # its ensure's, run either way.
    def begun(node)
      statements_of(node.statements) + rescued(node.rescue_clause) +
        clause_statements(node.else_clause) +
        clause_statements(node.ensure_clause)
    end

    # The statements of clause, a rescue, then of each rescue
    # after it; none for none.
    def rescued(clause)
      return [] if clause.nil?

      statements_of(clause.statements) + rescued(clause.subsequent)
    end
  end
end
