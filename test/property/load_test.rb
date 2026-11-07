require_relative '../test_helper'
require_relative 'method_grammar'
require 'path_coverage/kernel'
require 'path_coverage/manifest'
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

  private

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
