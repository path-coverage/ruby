require 'prism'
require_relative 'paths_tree'
require_relative 'decision'
require_relative 'loop_forks'
require_relative 'loop_nodes'
require_relative 'manifest'
require_relative 'method_statements'
require_relative 'rescue_forks'

module PathCoverage
  # The loops of each method: the blocks, lambdas, whiles, untils
  # and fors in its body, each run 0 or more times, and which of
  # them hold each of its rows, as a call's Walk takes them; a
  # while's or until's body holds its rows, its test only its
  # first run's, as Walk's repeats have them.
  module MethodLoops
    # { def decision => { name => the loops holding it, outermost
    #   first } } for each def in source, at path. It holds each of
    # its rows, as MethodStatements gives them, and each of its
    # rescue forks, as RescueForks gives them. It also holds each
    # loop holding one of those, or forking, as LoopForks finds
    # them. Each is by name, as Decision names where it starts.
    def self.of(source, path, decisions = nil)
      decisions ||= Manifest.decisions(source, path)
      spots = spots_in(source, path, decisions)
      forks = LoopForks.of(source, path, decisions)
      starts = PathsTree.line_starts(source)
      LoopNodes.defs(Prism.parse(source).value).to_h do |node|
        decision = Decision.of(path, node)
        loops = [named(node, path), forks[decision].keys]
        [decision, holding(spots.fetch(decision), loops, starts)]
      end
    end

    # A spot a loop can hold, named where it is, like a row.
    Spot = Data.define(:name, :line, :column)

    # The lines of the defs in source whose body's rescue retries.
    # A retry there restarts the method's frame, so Ruby reports a
    # call of it again, with no return of the first.
    def self.restarts(source)
      defs = LoopNodes.defs(Prism.parse(source).value)
      defs.filter_map do |node|
        node.location.start_line if restarting?(node.body)
      end.to_set
    end

    # True for body, a def's, when a retry restarts it: a begin of
    # the def's own whose rescue retries. An empty body is nil.
    def self.restarting?(body)
      return false if body.nil?

      LoopNodes.implicit?(body) && LoopNodes.loop?(body)
    end

    # { def decision => its spots } for each def in source, at
    # path. Its spots are its rows, as MethodStatements gives them,
    # and the Spot of each of its rescue forks.
    def self.spots_in(source, path, decisions)
      rows = MethodStatements.of(source, path, decisions)
      rescues = RescueForks.of(source, path)
      rows.to_h do |decision, held|
        [decision, held + spots_of(rescues.fetch(decision))]
      end
    end

    # The Spot of each rescue fork of forks, a def's, as
    # RescueForks gives them.
    def self.spots_of(forks)
      forks.keys.map do |name|
        line, column = name.split(':').last(2).map(&:to_i)
        Spot.new(name:, line:, column:)
      end
    end

    # { loop's name => where its first statement starts, a byte
    #   offset } of each loop in source, at path, holding a row or
    # forking, as loops, the result of of, has them: where a pass
    # call goes.
    def self.passes(source, path, loops)
      held = loops.values.flat_map { _1.to_a.flatten }.to_set
      defs = LoopNodes.defs(Prism.parse(source).value)
      nodes = defs.flat_map { LoopNodes.loops_in(_1.body) }
      nodes.filter_map { pass_at(_1, path, held) }.to_h
    end

    # [name, offset] of node, a loop, where its pass call goes,
    # when it is among held and its body has a statement; else nil.
    def self.pass_at(node, path, held)
      name = Decision.at(path, LoopNodes.at(node))
      return unless held.include?(name) && !LoopNodes.modifier?(node)

      first = LoopNodes.first_statement(LoopNodes.body_of(node))
      [name, first.location.start_offset] if first
    end

    # [[name, location], ...] of the loops in node's body, a def's,
    # in the order they start, each location the source holding
    # its rows: a block's or lambda's whole, a keyword loop's body;
    # none of a keyword loop with an empty body.
    def self.named(node, path)
      LoopNodes.loops_in(node.body).filter_map do |loop|
        keyword = LoopNodes::KEYWORDS.include?(loop.type)
        held = keyword ? loop.statements : loop
        [Decision.at(path, LoopNodes.at(loop)), held.location] if held
      end
    end

    # { def decision => { row's name => the name of the while or
    #   until whose test holds it } } for each def in source, at
    # path: rows whose later runs repeat the loop's first, so take
    # no step, as Walk's repeats have them.
    def self.repeats(source, path, decisions = nil)
      rows = MethodStatements.of(source, path, decisions)
      starts = PathsTree.line_starts(source)
      LoopNodes.defs(Prism.parse(source).value).to_h do |node|
        decision = Decision.of(path, node)
        tests = tests_in(node.body, path)
        [decision, tested(rows[decision], tests, starts)]
      end
    end

    # { row's name => the loop whose test holds it } of each of
    # rows in one of tests, as tests_in gives them.
    def self.tested(rows, tests, starts)
      rows.filter_map do |row|
        loop = around(tests, starts[row.line - 1] + row.column).first
        [row.name, loop] if loop
      end.to_h
    end

    # [[name, location], ...] of the test of each while and until
    # in node's body, by its loop's name.
    def self.tests_in(node, path)
      LoopNodes.loops_in(node).filter_map do |loop|
        next unless %i[while_node until_node].include?(loop.type)

        name = Decision.at(path, LoopNodes.at(loop))
        [name, loop.predicate.location]
      end
    end

    # { name => the loops holding it, outermost first } of each of
    # rows, of each loop holding one, and of each of forked, the
    # names of the loops that fork; loops is [[name, location],
    # ...] in the order they start.
    def self.holding(rows, (loops, forked), starts)
      held = rows.to_h do |row|
        [row.name, around(loops, starts[row.line - 1] + row.column)]
      end
      held.merge(outer((held.values.flatten + forked).uniq, loops))
    end

    # { name => the loops holding it, outermost first } of each
    # loop named in names; loops as holding has them.
    def self.outer(names, loops)
      locations = loops.to_h
      names.to_h do |name|
        [name, around(loops, locations[name].start_offset) - [name]]
      end
    end

    # The names of the loops whose source holds the byte at
    # offset, outermost first.
    def self.around(loops, offset)
      loops.filter_map do |name, location|
        name if (location.start_offset...location.end_offset)
                .cover?(offset)
      end
    end
  end
end
