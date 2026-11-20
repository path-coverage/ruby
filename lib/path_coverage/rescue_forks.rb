require 'prism'
require_relative 'decision'
require_relative 'leaving'

module PathCoverage
  # The rescue forks of each def. Each begin with a rescue forks
  # there, whether it is a def's body, a block's, or nested in a
  # body. Either its body completes, or one of its rescues runs.
  module RescueForks
    # Example: { "k.rb:1:0" => { "k.rb:3:0" => [1, 0...30, 14...20,
    # [38...40]] } } for a def at line 1 whose one rescue is at
    # line 3.
    # { def decision => { fork's name => [its rescues, its begin's
    # byte range, its body's, [each rescue's body's]] } } for each
    # def in source, at path. A fork is named where its first
    # rescue is.
    def self.of(source, path)
      found(source, path).forks
    end

    # The Found that has visited each def in source, at path.
    def self.found(source, path)
      found = Found.new(path)
      Prism.parse(source).value.accept(found)
      found
    end

    # Finds the rescue fork of each def it visits.
    class Found < Prism::Visitor
      # Starts with no def visited. Forks are named as at path.
      def initialize(path)
        @path = path
        @forks = {}
        @completions = {}
        @starts = {}
        @values = {}
        @def = nil
        super()
      end

      # forks is { def decision => { fork's name => [its rescues,
      # its begin's byte range, its body's, [each rescue's body's]]
      # } }.
      # completions is { fork's name => where its body completes }.
      # starts is { [fork's name, rescue's number] => the byte
      # offset where that rescue starts to run }. values is { fork's
      # name => the byte range of a rescue modifier's rescue, its
      # value }.
      attr_reader :forks, :completions, :starts, :values

      # Visits inside node, a def, noting the rescue forks in it as
      # its own.
      def visit_def_node(node)
        outer = @def
        @def = Decision.of(@path, node)
        @forks[@def] = {}
        super
        @def = outer
      end

      # Notes node, a begin, as a rescue fork of the def it is in,
      # when it has a rescue, then visits inside it. A def's body
      # with a rescue is a begin, and so is a block's.
      def visit_begin_node(node)
        note_fork(node) unless @def.nil? || node.rescue_clause.nil?
        super
      end

      # Notes node, a rescue modifier, x rescue y, as a rescue fork
      # of the def it is in, then visits inside it. Its body is x,
      # and its one rescue is y. Its name is where its rescue is.
      def visit_rescue_modifier_node(node)
        note_modifier(node) unless @def.nil?
        super
      end

      # Notes the rescue fork of node, a rescue modifier.
      def note_modifier(node)
        name = Decision.at(@path, node.keyword_loc)
        body = span(node.expression.location)
        value = span(node.rescue_expression.location)
        @forks[@def][name] = [1, span(node.location), body, [value]]
        note_value(name, node.expression, value)
      end

      # Notes where the rescue modifier named name completes and
      # where its rescue runs. It completes at expression, wrapped,
      # unless that leaves. Its rescue runs at value, wrapped.
      def note_value(name, expression, value)
        if Leaving.word(expression).nil?
          @completions[name] = span(expression.location)
        end
        @values[name] = value
      end

      # The byte range of location.
      def span(location)
        location.start_offset...location.end_offset
      end

      # Notes the rescue fork of node, a begin with a rescue. Its
      # name is where its first rescue is.
      def note_fork(node)
        clause = node.rescue_clause
        name = Decision.at(@path, clause.location)
        note_completion(name, node.statements, clause)
        count = noted(name, clause, 1)
        @forks[@def][name] = [count, *spans_of(node, clause)]
      end

      # [the byte range of node, a begin, of its body, and of the
      # body of each rescue from clause, its first].
      def spans_of(node, clause)
        whole = node.location
        body = range_of(node.statements, clause.location.start_offset)
        clauses = []
        until clause.nil?
          clauses << range_of(clause.statements,
                              header_end(clause))
          clause = clause.subsequent
        end
        [whole.start_offset...whole.end_offset, body, clauses]
      end

      # The byte range of statements, or an empty range at offset
      # when there are none.
      def range_of(statements, offset)
        return offset...offset if statements.nil?

        loc = statements.location
        loc.start_offset...loc.end_offset
      end

      # Notes where a body of statements completes. name is its
      # fork's name, and clause its first rescue. An empty body
      # completes at clause, by a byte offset, for a statement of
      # its own. Otherwise it completes at its last statement, by
      # its byte range, to wrap. A last statement that leaves is
      # not noted, because that body never completes.
      def note_completion(name, statements, clause)
        if statements.nil?
          return @completions[name] = clause.location.start_offset
        end

        last = statements.body.last
        return unless Leaving.word(last).nil?

        loc = last.location
        @completions[name] = loc.start_offset...loc.end_offset
      end

      # How many rescues the fork named name has, counting from
      # clause, the rescue numbered number. It notes where each
      # rescue starts to run, after its header. Once the rescues
      # run out it gives number less one.
      def noted(name, clause, number)
        return number - 1 if clause.nil?

        @starts[[name, number]] = header_end(clause)
        noted(name, clause.subsequent, number + 1)
      end

      # The byte offset where the header of clause, a rescue, ends.
      # The header is its keyword, its exceptions, its => and
      # reference, and its then, whichever of them it has.
      def header_end(clause)
        nodes = [*clause.exceptions, clause.reference].compact
        locs = [clause.keyword_loc, clause.operator_loc,
                clause.then_keyword_loc].compact
        (nodes.map(&:location) + locs).map(&:end_offset).max
      end
    end
  end
end
