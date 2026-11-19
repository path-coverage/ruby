require 'prism'
require_relative 'card_tree'
require_relative 'card_ways'
require_relative 'decision_paths'
require_relative 'manifest'
require_relative 'loop_forks'
require_relative 'method_statements'
require_relative 'way_algebras'

module PathCoverage
  # The ways one call can take through each method, each listed as
  # its steps, as a call's trace records them: a decision's
  # [name, path], or any other row's [name], eg a return's.
  module MethodWays
    # { def decision => [way, ...] } for each def in source, at
    # path, its decisions those of no settings: the ways some call
    # can take, each loop a fork when loops.
    def self.of(source, path, loops: false)
      split(source, path, loops:).transform_values(&:first)
    end

    # { def decision => [possible, impossible] } for each def in
    # source, at path, its decisions those of no settings: the
    # ways some call can take, and those none can, as giving a
    # leaf StableLeaves finds both outcomes; each loop a fork when
    # loops, as LoopForks finds them.
    def self.split(source, path, loops: false)
      decisions = Manifest.decisions(source, path)
      cards = MethodStatements.of(source, path, decisions)
      forks = LoopForks.of(source, path, decisions)
      cards.to_h do |key, rows|
        forked = loops ? forks.fetch(key) : {}
        [key, split_card(source, decisions, rows, forked)]
      end
    end

    # [possible, impossible] of the card of rows in source, as
    # split gives them, each loop of forks a fork; a way giving no
    # items to a loop declared never empty is impossible.
    def self.split_card(source, decisions, rows, forks = {})
      possible, all = [true, false].map do |stable|
        listed(source, decisions, rows, [stable, forks])
      end
      lines = never_empty(source)
      by = possible.group_by { empties?(_1, lines) }
      possible = by.fetch(false, [])
      [possible, all - possible]
    end

    # The comment on a loop's line declaring it is never given no
    # items.
    NEVER_EMPTY = '# path: impossible 0 items'.freeze

    # The numbers of the lines of source with a comment holding
    # NEVER_EMPTY.
    def self.never_empty(source)
      Prism.parse(source).comments.filter_map do |comment|
        location = comment.location
        location.start_line if location.slice.include?(NEVER_EMPTY)
      end.to_set
    end

    # True for a way giving no items to a loop on one of lines.
    def self.empties?(way, lines)
      way.any? do |name, path|
        line = Integer(name.split(':')[-2])
        path == [FORKS[0]] && lines.include?(line)
      end
    end

    # The steps of a loop's fork, by its path: no pass, or some.
    FORKS = ['0 items', '1+ items'].freeze

    # The ways through the card of rows, as steps, those no call
    # can take too unless stable, each loop of forks a fork.
    def self.listed(source, decisions, rows, (stable, forks))
      ways = CardWays.card(source, decisions, rows,
                           WayAlgebras::Listed, [stable, forks])
      steps = rows.to_h { [CardTree.key_of(_1), _1] }
      loops = forks.keys.to_h { [CardTree.key_at(_1), _1] }
      ways.map do |way|
        way.map do |key, index|
          next [loops[key], [FORKS[index]]] if loops.key?(key)

          step(steps, decisions, key, index)
        end
      end
    end

    # The ways, as of lists them, that way, a call's, as its trace
    # records it, witnesses: each pass of a loop inlined, one way
    # for each distinct way its passes took, a loop with no pass
    # adding nothing; each way's steps in the order their rows are
    # written, as ordered gives them. A loop of forked, the names
    # of loops that fork, that made a pass steps 1+ items first.
    def self.witnessed(way, forked = [])
      found = way.reduce([[]]) do |ways, step|
        next ways.map { _1 + [step] } if step.size < 3

        ways.product(passes(step, forked)).map { _1.sum([]) }
      end
      found.to_set { ordered(_1) }
    end

    # The ways a loop's step, [name, items, pass ways], inlines:
    # each way its passes witness, after a step of 1+ items when
    # the loop is among forked; or the one way of no steps when it
    # made no pass.
    def self.passes(step, forked)
      taken = step[2].flat_map { witnessed(_1, forked).to_a }
      return [[]] if taken.empty?
      return taken unless forked.include?(step[0])

      taken.map { [[step[0], [FORKS[1]]], *_1] }
    end

    # way, a static way, as the way witnessed gives a call that
    # took it: with no step of 0 items, as a loop that made no
    # pass is no step of a call's trace, its steps ordered.
    def self.matched(way)
      by = way.group_by { _1[1] == [FORKS[0]] }
      ordered(by.fetch(false, []))
    end

    # way's steps in the order their rows are written, by line
    # then column, so a way is compared by its steps alone.
    def self.ordered(way)
      way.sort_by { |step| step[0].split(':').last(2).map(&:to_i) }
    end

    # The step of the path at index of the row keyed key, among
    # rows, { key => row }: a decision's [name, path], decisions
    # being { decision => Condition }; any other's [name].
    def self.step(rows, decisions, key, index)
      row = rows[key]
      return [row.name] if row.decision.nil?

      possible = DecisionPaths.possible(decisions[row.decision])
      [row.decision, possible[index]]
    end
  end
end
