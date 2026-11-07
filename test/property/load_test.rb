require_relative '../test_helper'
require_relative 'method_grammar'
require 'path_coverage/card_ways'
require 'path_coverage/way_algebras'
require 'path_coverage/decision_paths'
require 'path_coverage/kernel'
require 'path_coverage/manifest'
require 'path_coverage/method_statements'
require 'path_coverage/rewriter'
require 'prism'

class PropertyLoadTest < TidTest
  # Its test starts path_coverage, which swaps the one global load
  # hook.
  serial!

  SEEDS = (1..40)

  test 'Pq3L10', %w(
  | Every method MethodGrammar generates from SEEDS loads under
  | path coverage and, on every combination of its parameters,
  | returns or raises exactly as it does when Ruby loads it plainly.
  ) do |t|
    sources = SEEDS.to_h { [_1, MethodGrammar.new(_1).source] }
    sources.each { |seed, source| t.write(source, "s#{seed}.rb") }
    t.start
    plain = sources.transform_values { outcomes(plainly(_1)) }
    covered = sources.to_h do |seed, _|
      [seed, outcomes(t.load("s#{seed}.rb")::Snippet)]
    end
    assert_equal plain, covered
  end

  test 'Pq3L11', %w(
  | For every method MethodGrammar generates from SEEDS, and for
  | that method broken by dropping its last end, path coverage's
  | rewrite parses exactly when the source does: it never breaks
  | valid code, nor makes broken code valid.
  ) do
    sources = SEEDS.flat_map do |seed|
      source = MethodGrammar.new(seed).source
      [source, source.sub(/end\s*\z/, '')]
    end
    expected = sources.map { parses?(_1) }
    actual = sources.map { parses?(rewrite_of(_1)) }
    assert_equal expected, actual
  end

  test 'Pq3L12', %w(
  | Every method MethodGrammar generates with reuse from SEEDS,
  | its leaves often repeating a parameter, has as its possible
  | ways, as CardWays lists them, exactly the ways its calls take
  | over every combination of its parameters, each way the path
  | it takes at every row it reaches. No way taken is missing,
  | so none is ever ruled out wrongly; and no way listed is
  | never taken, so none that no input can take is counted.
  ) do |t|
    sources = SEEDS.to_h do |seed|
      [seed, MethodGrammar.new(seed, reuse: true).source]
    end
    sources.each { |seed, source| t.write(source, "r#{seed}.rb") }
    t.start
    taken = sources.to_h do |seed, source|
      [seed, taken_ways(t, "r#{seed}.rb", source)]
    end
    listed = sources.to_h do |seed, source|
      [seed, listed_ways(source, "r#{seed}.rb")]
    end
    none = SEEDS.to_h { [_1, []] }
    missing = SEEDS.to_h { [_1, taken[_1] - listed[_1]] }
    impossible = SEEDS.to_h { [_1, listed[_1] - taken[_1]] }
    assert_equal none, missing
    assert_equal none, impossible
  end

  private

  # The ways CardWays lists through the one card of source, the
  # file name, each way's labels in order, and the ways in order.
  def listed_ways(source, name)
    listed = PathCoverage::WayAlgebras::Listed
    ways = PathCoverage::CardWays.of(source, name, listed)
    ways.values.first.map(&:sort).uniq.sort
  end

  # The distinct ways the Snippet of the file name, source,
  # loaded under fixture's run, takes over every combination of
  # its parameters, each as listed_ways gives them.
  def taken_ways(fixture, name, source)
    snippet = fixture.load(name)::Snippet
    decisions = PathCoverage::Manifest.decisions(source, name)
    rows = PathCoverage::MethodStatements.of(source, name,
                                             decisions)
    rows = rows.values.first
    arity = snippet.method(:run).arity
    ways = [true, false].repeated_permutation(arity).map do |args|
      way_on(snippet, args, rows, decisions)
    end
    ways.uniq.sort
  end

  # The way snippet's run takes on args: the label of each path of
  # a row of rows that the call counted, as recorded_labels gives
  # them, in order.
  def way_on(snippet, args, rows, decisions)
    before = recorded_labels(rows, decisions)
    call(snippet, args)
    after = recorded_labels(rows, decisions)
    (after - before).map(&:first).sort
  end

  # [[row key, path index], count] for each path of a decision
  # row of rows recorded so far, the index among its decision's
  # possible paths, in decisions, and [[row key, 0], runs] for
  # each other row, a return or a raise, reached.
  def recorded_labels(rows, decisions)
    names = rows.map(&:name)
    reached = PathCoverage.recorder.reached.slice(*names)
    path_labels(names, decisions) +
      reached.map { |name, n| [[key(name), 0], n] }
  end

  # [[row key, path index], count] for each path recorded so far
  # of the decision of each of names, rows' names, the index
  # among its decision's possible paths, in decisions.
  def path_labels(names, decisions)
    paths = PathCoverage.recorder.decision_paths.slice(*names)
    paths.flat_map do |name, counts|
      possible = decision_paths(decisions.fetch(name))
      counts.map { |path, n| [[key(name), possible.index(path)], n] }
    end
  end

  # The possible paths of condition.
  def decision_paths(condition)
    PathCoverage::DecisionPaths.possible(condition)
  end

  # The line:column key of a row's name.
  def key(name)
    name.split(':').last(2).join(':')
  end

  # Calls snippet's run with args, a Stop it raises being a way
  # of leaving like any other.
  def call(snippet, args)
    snippet.run(*args)
  rescue snippet::Stop
    nil
  end

  # The Snippet module source defines, loaded plainly, with no
  # path coverage.
  def plainly(source)
    wrapper = Module.new
    wrapper.module_eval(source)
    wrapper::Snippet
  end

  # What snippet's run gives on each combination of its
  # parameters, in order: its value, or :raised for a Stop.
  def outcomes(snippet)
    arity = snippet.method(:run).arity
    [true, false].repeated_permutation(arity).map do |args|
      snippet.run(*args)
    rescue snippet::Stop
      :raised
    end
  end

  # Path coverage's rewrite of source.
  def rewrite_of(source)
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    PathCoverage::Rewriter.rewrite(source, decisions)
  end

  # True when code parses with no errors.
  def parses?(code)
    Prism.parse(code).errors.empty?
  end
end
