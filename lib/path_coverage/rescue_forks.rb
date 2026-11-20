require 'prism'
require_relative 'decision'
require_relative 'leaving'

module PathCoverage
  # The rescue forks of each def: a body with a rescue forks there,
  # into its body completing, or its rescue running.
  module RescueForks
    # Example: { "k.rb:1:0" => { "k.rb:3:0" => 1 } } for a def at
    # line 1 whose rescue is at line 3.
    # { def decision => { fork's name => its rescues } } for each
    # def in source, at path, its fork named where its rescue is.
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
      # Starts with no def visited, its forks named as at path.
      def initialize(path)
        @path = path
        @forks = {}
        @completions = {}
        @starts = {}
        super()
      end

      # { def decision => { fork's name => its rescues } } of each
      # def visited; { fork's name => the byte range of the last
      # statement of its body }, where its body completes; and
      # { [fork's name, rescue's number] => the byte offset where
      # that rescue's body starts }, where it runs.
      attr_reader :forks, :completions, :starts

      # Notes the rescue fork of node, a def, then visits inside it.
      def visit_def_node(node)
        @forks[Decision.of(@path, node)] = forks_of(node.body)
        super
      end

      # { fork's name => its rescues } of body, a def's: none but
      # for a body with a rescue, whose begin starts at the def.
      def forks_of(body)
        clause = rescue_clause_of(body)
        return {} if clause.nil?

        name = Decision.at(@path, clause.location)
        note_completion(name, body.statements, clause)
        { name => noted(name, clause, 1) }
      end

      # Notes where a body of statements, with the rescue fork named
      # name, its first rescue clause, completes: for an empty body,
      # the byte offset of clause, for a statement of its own; else
      # the byte range of its last statement, to wrap, unless that
      # leaves the method, when the body never completes.
      def note_completion(name, statements, clause)
        if statements.nil?
          return @completions[name] = clause.location.start_offset
        end

        last = statements.body.last
        return unless Leaving.word(last).nil?

        loc = last.location
        @completions[name] = loc.start_offset...loc.end_offset
      end

      # How many rescues the fork named name has, noting where each
      # starts to run, after its header, from clause, its rescue
      # numbered number, on; number less one once the rescues have
      # run out.
      def noted(name, clause, number)
        return number - 1 if clause.nil?

        @starts[[name, number]] = header_end(clause)
        noted(name, clause.subsequent, number + 1)
      end

      # The byte offset where the header of clause, a rescue, ends:
      # after its keyword, its exceptions, its => and reference,
      # and its then, whichever of them it has.
      def header_end(clause)
        nodes = [*clause.exceptions, clause.reference].compact
        locs = [clause.keyword_loc, clause.operator_loc,
                clause.then_keyword_loc].compact
        (nodes.map(&:location) + locs).map(&:end_offset).max
      end

      # The first rescue of body, a def's, when its begin starts at
      # the def, as a rescue or an ensure makes it; nil for a body
      # with no rescue.
      def rescue_clause_of(body)
        body.rescue_clause if body.is_a?(Prism::BeginNode)
      end
    end
  end
end
