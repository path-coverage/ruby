require 'prism'
require_relative 'manifest'
require_relative 'manifest_chains'
require_relative 'manifest_choices'
require_relative 'decision'
require_relative 'decision_paths'
require_relative 'decision_tree'
require_relative 'statement_arms'
require_relative 'totals'

module PathCoverage
  # One row of a method's card, a top-level statement or a
  # decision at its top: where it starts; its top, what it is as
  # written, eg = for a write; how many paths it has; the name
  # of its decision, nil when it is no decision; and its own name, by
  # where it is, eg "k.rb:2:2".
  Statement = Data.define(:line, :column, :top, :paths, :decision,
                          :name)

  # Finds, without running it, the top-level statements of each
  # method in source, one row each in its method's card.
  module MethodStatements
    # Each function below takes decisions, { decision =>
    # Condition }, the decisions the run has in source, as
    # Manifest.parse gives them with the run's ignore and treat
    # settings; nil for those of no settings.

    # { def decision => [Statement, ...] } for each def in source.
    # Example: def f; x = 1; x; end gives = and value rows.
    def self.of(source, path, decisions = nil)
      collect(source, path, decisions).methods
    end

    # { def decision => its name } for each def in source, eg
    # { "k.rb:4:2" => :ship }, each its card's title.
    def self.names(source, path, decisions = nil)
      collect(source, path, decisions).names
    end

    # { def decision => its last line } for each def in source, eg
    # { "k.rb:4:2" => 6 }, where its card ends.
    def self.lasts(source, path, decisions = nil)
      collect(source, path, decisions).lasts
    end

    # Example: { "k.rb:2:2" => 18 } for a write at byte 18.
    # Where a call can count the runs of each row that is no
    # decision, in every def in source, by the row's name, where it
    # starts: its byte offset, or, in an endless def, whose body
    # is one expression, its byte range, to be wrapped.
    def self.reaches(source, path, decisions = nil)
      collect(source, path, decisions).reaches
    end

    # A Collector that has visited each def in source, with
    # decisions, or, for nil, those of no settings.
    def self.collect(source, path, decisions)
      decisions = Manifest.decisions(source, path) if decisions.nil?
      collector = Collector.new(path, decisions)
      Prism.parse(source).value.accept(collector)
      collector
    end

    # Example: RATE = x ? 2 : 1 at the top level, its then
    # taken, gives [1, 2].
    # [taken, possible] of the paths of the decisions in source on
    # no method's card, outside every def, as top_rows gives
    # them; paths as Result#paths gives them.
    def self.top_level(source, path, paths, decisions = nil)
      names = top_rows(source, path, decisions).map(&:decision)
      Totals.alone(paths.slice(*names))
    end

    # Example: RATE = x ? 2 : 1 gives a ?: row at 1:9.
    # A Statement row for each decision in source on no method's
    # card, outside every def, for the card of its own lines, in
    # the order written: where decision mode names it, its
    # operator, an elsif's elsif, and its paths.
    def self.top_rows(source, path, decisions = nil)
      collector = collect(source, path, decisions)
      carded = collector.methods.values.flatten.map(&:decision)
      loose = collector.decisions.except(*carded)
      rows = loose.map do |name, decision|
        top_row(source, name, decision)
      end
      rows.sort_by { [_1.line, _1.column] }
    end

    # The Statement row of the decision named name, its Condition
    # decision, at the top level of source.
    def self.top_row(source, name, decision)
      line, column = name.split(':').last(2).map { Integer(_1) }
      top = if DecisionTree.elsif?(source,
                                   decision)
              'elsif'
            else
              decision.operator
            end
      paths = DecisionPaths.possible(decision).size
      Statement.new(line:, column:, top:, paths:, decision: name,
                    name:)
    end

    # Example: { "k.rb:1:0" => [2, 4] }, 2 of ship's 4 taken.
    # Each def's card total in source, [taken, size], its rows'
    # taken as taken gives them from paths and reached; a row
    # not known counts as not taken, never more than it ran.
    def self.totals(source, path, paths, reached, decisions = nil)
      of(source, path, decisions).transform_values do |rows|
        seen = taken(rows, paths, reached).compact.sum
        [seen, size(rows.map(&:paths))]
      end
    end

    # Example: 19:04, a statement on line 19 at column 4.
    # statement's line:column, the column two digits so they
    # line up.
    def self.at(statement)
      format('%<line>d:%<column>02d',
             line: statement.line, column: statement.column)
    end

    # Example: rows of 1, 2 and 2 paths, [1, 2, 2], have size 5.
    # The paths a method's tests are to take: paths, its rows'
    # paths, added up, each row's taken on its own.
    def self.size(paths)
      paths.sum
    end

    # Example: an if row with only its then taken gives 1.
    # How many paths of each row were taken: for a decision's row,
    # its paths with a count, paths being Result#paths; for any
    # other row, its 1 path when reached has a count for it, 0
    # when not, nil, not known, without reached.
    def self.taken(rows, paths, reached = nil)
      rows.map do |row|
        next taken_decision(row, paths) if row.decision
        next nil if reached.nil?

        reached.key?(row.name) ? 1 : 0
      end
    end

    # How many of a decision row's paths have a count in paths.
    def self.taken_decision(row, paths)
      counts = paths.fetch(row.decision).map { |each| each[:count] }
      counts.count(&:positive?)
    end

    # Collects each def's top-level statements.
    class Collector < Prism::Visitor
      include ManifestChains
      include ManifestChoices
      include StatementArms

      # Starts with no methods found; decisions are decision mode's,
      # { decision => Condition }.
      def initialize(path, decisions)
        @path = path
        @decisions = decisions
        @methods = {}
        @names = {}
        @lasts = {}
        @reaches = {}
        super()
      end

      # The methods found so far, { def decision => rows }; their
      # names and last lines, { def decision => name } and
      # { def decision => line }; where each row that is no
      # decision is reached, as MethodStatements.reaches has it;
      # and the decisions it was given, { decision => Condition }.
      attr_reader :methods, :names, :lasts, :reaches, :decisions

      # Notes node's name, its last line, its body statements as
      # its rows, those in its decisions' arms too, but only those
      # that shape its paths, as shapes? has it, none for an empty
      # body, and where each row that is no decision is reached.
      def visit_def_node(node)
        written = rows_in(statements_of(node.body))
        tops = written.select { shapes?(_1) }
        decision = Decision.of(@path, node)
        @methods[decision] = tops.map { |top| row_of(top) }
        note_def(decision, node)
        note_reaches(tops, endless: !node.equal_loc.nil?)
        super
      end

      # Notes the name and last line of node, the def at decision, and
      # where it is entered, reached under decision's own name, so its
      # card can say how many times it was called.
      def note_def(decision, node)
        @names[decision] = node.name
        @lasts[decision] = node.location.end_line
        @reaches[decision] = entry_at(node)
      end

      # Notes where each of tops that is no decision, a return or a
      # raise, is reached: its byte offset, or, endless, its byte
      # range.
      def note_reaches(tops, endless:)
        tops.each do |top|
          next if decision?(top)

          loc = top.location
          start = loc.start_offset
          at = endless ? start...loc.end_offset : start
          @reaches[Decision.at(@path, loc)] = at
        end
      end

      # Example: if a then x = 1 end gives the if, then the write.
      # The nodes statements' rows are for, flat, in the order
      # they are written: each statement's tops, each with the
      # decisions of their own inside it, in the order they are named,
      # eg a || before the ?: whose predicate it is, then the rows
      # of its arms' statements, when it has any.
      def rows_in(statements)
        statements.flat_map do |statement|
          tops = top_nodes(statement).flat_map do |top|
            named = [top, *inner_decisions(top)]
            ordered = named.sort_by { decision_loc(_1).start_offset }
            [*ordered, *rows_in(arms_of(top))]
          end
          tops + body_rows(statement)
        end
      end

      # The Statement row of node. A decision is where decision mode
      # names it, eg a modifier if at its keyword, with as many
      # paths as decision mode gives it. Anything else is where
      # it starts, with 1 path.
      def row_of(node)
        decision = decision_at(node)
        loc = decision ? decision_loc(node) : node.location
        name = Decision.at(@path, loc)
        Statement.new(
          line: loc.start_line, column: loc.start_column,
          top: top_of(node),
          paths: decision ? DecisionPaths.possible(decision).size : 1,
          decision: decision ? name : nil, name:
        )
      end

      # Example: x = (a ? 1 : 2) + (b ? 3 : 4) gives both ?:s.
      # The nodes statement's rows are for: the outermost decisions
      # in it, in the order they run, as what holds them is
      # looked through; statement itself when it holds none.
      def top_nodes(statement)
        tops = decisions_in(statement)
        tops.empty? ? [statement] : tops
      end

      # node when it is a decision, else the outermost decisions in
      # its children, in order; none in a body or a def, as UNSEEN
      # has them.
      def decisions_in(node)
        return [node] if decision?(node)
        return [] if UNSEEN.include?(node.type)

        node.compact_child_nodes.flat_map do |child|
          decisions_in(child)
        end
      end

      # True when decision mode has a decision named where node's
      # decision would start.
      def decision?(node)
        !decision_at(node).nil?
      end

      # Decision mode's Condition for the decision named where
      # node's decision would start; nil when it has none there.
      def decision_at(node)
        @decisions[decision_name(node)]
      end

      # The name node's decision would have, by where it would start.
      def decision_name(node)
        Decision.at(@path, decision_loc(node))
      end

      TOPS = {
        call_node: '()', return_node: 'return', def_node: 'def'
      }.freeze

      # What statement is as written: a decision's operator, eg if,
      # when decision mode has a decision where it starts, an elsif
      # being elsif, as written, an if or unless with an else
      # if/else or unless/else; else = for a write, () for a
      # call, raise for a raise of the method's own, as it leaves
      # the method, return for a return, def for a def inside it,
      # value for anything else.
      def top_of(statement)
        decision = decision_at(statement)
        return 'elsif' if decision && elsif?(statement)
        return with_else(decision.operator, statement) if decision
        return 'raise' if raise?(statement)
        return '=' if write?(statement)

        TOPS.fetch(statement.type, 'value')
      end

      # True for an if written as an elsif.
      def elsif?(statement)
        statement.type == :if_node && statement.if_keyword == 'elsif'
      end

      # True for a write of any kind: of a variable, eg @x = 1
      # or x += 1, or a call Ruby makes of an index or attribute
      # write, eg a[i] = x or a.b = x.
      def write?(statement)
        statement.type.end_with?('_write_node') ||
          (statement.type == :call_node && statement.attribute_write?)
      end

      # True when statement is a call of raise with no receiver.
      def raise?(statement)
        statement.type == :call_node && statement.receiver.nil? &&
          statement.name == :raise
      end
    end
  end
end
