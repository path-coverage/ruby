require_relative '../test_helper'
require_relative 'method_grammar'
require 'path_coverage/kernel'

class PropertyLoadTest < TidTest
  # Its test starts path_coverage, which swaps the one global load
  # hook.
  serial!

  SEEDS = (1..40).freeze

  test 'Pq3L10', %w(
  | Every method MethodGrammar generates from SEEDS loads under
  | path coverage and, on every combination of its parameters,
  | returns or raises exactly as it does when Ruby loads it plainly.
  ) do |t|
    sources = SEEDS.to_h { [_1, MethodGrammar.new(_1).source] }
    sources.each { |seed, source| t.write(source, "s#{seed}.rb") }
    t.start
    differences = sources.filter_map do |seed, source|
      difference(seed, source, t)
    end
    assert differences.empty?, differences.join("\n")
  end

  private

  # Nil when the method seed generated, source, loads under path
  # coverage and behaves as it does loaded plainly; else what
  # differs, with the source.
  def difference(seed, source, fixture)
    plain = Module.new
    plain.module_eval(source)
    covered = fixture.load("s#{seed}.rb")::Snippet
    expected = outcomes(plain::Snippet)
    actual = outcomes(covered)
    return if expected == actual

    "seed #{seed}: plain #{expected} covered #{actual}\n#{source}"
  rescue SyntaxError => e
    why = e.message.lines.grep(/unexpected/).first.to_s.strip
    "seed #{seed}: does not load: #{why}\n#{source}"
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
end
