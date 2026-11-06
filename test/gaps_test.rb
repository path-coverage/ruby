require_relative 'test_helper'
require 'path_coverage/gaps'
require 'path_coverage/result'

class GapsTest < TidTest
  test 'ngWa20', %w(
  | a path needing the outcome a fixed leaf can never have
  | is impossible, so it is never a gap
  ) do
    # @clock = options[:clock] || MonotonicClock.new
    fixed = { 54...72 => :truthy }
    decisions = {
      'k.rb:2:11' => condition('||', 35...50, 54...72, fixed:)
    }
    counts = {
      ['k.rb:2:11', 0] => { truthy: 1, falsy: 1 },
      ['k.rb:2:11', 1] => { truthy: 1, falsy: 0 }
    }
    decision_paths = {
      'k.rb:2:11' => { [true, nil] => 1, [false, true] => 1 }
    }
    result = PathCoverage::Result.new(decisions, counts,
                                      decision_paths)
    texts = {
      'k.rb:2:11' => ['options[:clock]', 'MonotonicClock.new']
    }
    actual = PathCoverage::Gaps.lines(
      result.operands, paths: result.paths, texts:
    )
    assert_equal [], actual
  end

  test 'ngWa40', %w(
  | each path a decision never took is a gap, named by the
  | outcome of each leaf it reaches, each leaf quoted as a
  | code span, so its text can hold commas and spaces
  ) do
    paths = [
      { path: [true, true], count: 2 },
      { path: [true, false], count: 0 },
      { path: [false, nil], count: 0 }
    ]
    texts = ['ok?(id)', 'fetch(:a, 1)']
    never = 'k.rb:2:2 path never taken: `ok?(id)`'
    expected = [
      "#{never} true, `fetch(:a, 1)` false",
      "#{never} false"
    ]
    gaps = PathCoverage::Gaps
    actual = gaps.path_gaps('k.rb:2:2', paths, texts)
    assert_equal expected, actual
  end

  test 'ngWa41', %w(
  | a leaf holding backticks is quoted, as a markdown code
  | span is, by a run of backticks one longer than its
  | longest, with a space inside when it starts or ends
  | with one, so the quoting is never ambiguous
  ) do
    code = PathCoverage::Gaps.method(:code)
    assert_equal '``a`b``', code.call('a`b')
    assert_equal '`` `ls` ``', code.call('`ls`')
    assert_equal '``` x == ``y`` ```', code.call('x == ``y``')
  end

  test 'ngWa42', %w(
  | a leaf written over several lines is quoted on one, each
  | run of whitespace a single space, so each gap is one
  | line; the decision's path:line:column still pins it
  ) do
    text = "user.member?(\n  order.id)"
    actual = PathCoverage::Gaps.code(text)
    assert_equal '`user.member?( order.id)`', actual
  end

  test 'ngWa50', %w(
  | the gap lines are each decision's paths never taken, in
  | manifest order, and one line for a decision never reached
  ) do
    decisions = {
      'k.rb:2:2' => condition('&&', 16...23, 27...35),
      'k.rb:6:4' => condition('&&', 57...64, 68...77)
    }
    counts = {
      ['k.rb:2:2', 0] => { truthy: 2, falsy: 1 },
      ['k.rb:2:2', 1] => { truthy: 0, falsy: 2 }
    }
    decision_paths = {
      'k.rb:2:2' => { [true, false] => 2, [false, nil] => 1 }
    }
    result = PathCoverage::Result.new(decisions, counts,
                                      decision_paths)
    texts = {
      'k.rb:2:2' => ['ok?(id)', 'new?(id)'],
      'k.rb:6:4' => ['ok?(id)', 'old?(id)']
    }
    expected = [
      'k.rb:2:2 path never taken: `ok?(id)` true, `new?(id)` true',
      'k.rb:6:4 never reached'
    ]
    actual = PathCoverage::Gaps.lines(
      result.operands, paths: result.paths, texts:
    )
    assert_equal expected, actual
  end

  test 'ngWa60', %w(
  | Example: if ready?(id) then ship(id) end, never reached
  | Its predicate is its one leaf, which never ran.
  | So the decision gets one line, saying it was never reached.
  ) do
    decisions = {
      'k.rb:4:4' => condition('if', 47...56, arm(:then, 62...70))
    }
    result = PathCoverage::Result.new(decisions, {}, {})
    texts = { 'k.rb:4:4' => ['ready?(id)'] }
    actual = PathCoverage::Gaps.lines(
      result.operands, paths: result.paths, texts:
    )
    assert_equal ['k.rb:4:4 never reached'], actual
  end
end
