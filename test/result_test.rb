require_relative 'test_helper'
require 'path_coverage/result'

class ResultTest < TidTest
  test 'DYTY10', %w(
  | the result lists every decision in the manifest
  | with the counts of each of its operands,
  | zero for an operand or a whole decision that never ran
  ) do
    decisions = {
      'k.rb:2:2' => condition('&&', 16...23, 27...35),
      'k.rb:6:4' => condition('&&', 57...64, 68...77)
    }
    counts = {
      ['k.rb:2:2', 0] => { truthy: 2, falsy: 1 },
      ['k.rb:2:2', 1] => { truthy: 1, falsy: 1 }
    }
    expected = {
      'k.rb:2:2' => [
        { truthy: 2, falsy: 1 },
        { truthy: 1, falsy: 1 }
      ],
      'k.rb:6:4' => [
        { truthy: 0, falsy: 0 },
        { truthy: 0, falsy: 0 }
      ]
    }
    actual = PathCoverage::Result.new(decisions, counts).operands
    assert_equal expected, actual
  end

  test 'DYTY20', %w(
  | the counts of a leaf that can have one outcome only
  | say which, so reporters demand that outcome alone
  ) do
    fixed = { 54...72 => :truthy }
    decisions = {
      'k.rb:2:11' => condition('||', 35...50, 54...72, fixed:)
    }
    counts = {
      ['k.rb:2:11', 0] => { truthy: 1, falsy: 1 },
      ['k.rb:2:11', 1] => { truthy: 1, falsy: 0 }
    }
    expected = {
      'k.rb:2:11' => [
        { truthy: 1, falsy: 1 },
        { truthy: 1, falsy: 0, only: :truthy }
      ]
    }
    actual = PathCoverage::Result.new(decisions, counts).operands
    assert_equal expected, actual
  end

  test 'DYTY40', %w(
  | the result lists every possible path of every decision, in
  | order, with how many evaluations took it, zero for a
  | path never taken and for every path of a decision never run
  ) do
    decisions = {
      'k.rb:2:2' => condition('&&', 16...23, 27...35),
      'k.rb:6:4' => condition('||', 57...64, 68...77)
    }
    decision_paths = {
      'k.rb:2:2' => { [true, false] => 2, [false, nil] => 1 }
    }
    expected = {
      'k.rb:2:2' => [
        { path: [true, true], count: 0 },
        { path: [true, false], count: 2 },
        { path: [false, nil], count: 1 }
      ],
      'k.rb:6:4' => [
        { path: [true, nil], count: 0 },
        { path: [false, true], count: 0 },
        { path: [false, false], count: 0 }
      ]
    }
    result = PathCoverage::Result.new(decisions, {}, decision_paths)
    assert_equal expected, result.paths
  end

  test 'DYTY50', %w(
  | Example: u.name&.size with name treated as present, run
  | once with name nil
  | That path is not one of the decision's possible paths.
  | So outside lists it, with how many evaluations took it.
  | A decision whose every path taken is possible is not listed.
  ) do
    fixed = { 11...17 => :present }
    decisions = {
      'k.rb:1:11' => condition('&.', 11...17, fixed:),
      'k.rb:2:11' => condition('&.', 31...37)
    }
    decision_paths = {
      'k.rb:1:11' => { ['not nil'] => 3, ['nil'] => 1 },
      'k.rb:2:11' => { ['nil'] => 2 }
    }
    result = PathCoverage::Result.new(decisions, {}, decision_paths)
    expected = { 'k.rb:1:11' => { ['nil'] => 1 } }
    assert_equal expected, result.outside
  end

  test 'DYTY51', %w(
  | Example: u.name&.size and v.name&.size, name treated as
  | present, each run once with name nil
  | The treatment is wrong at both decisions, so outside lists
  | both, each with how many evaluations took its nil path.
  ) do
    present = lambda do |range|
      condition('&.', range, fixed: { range => :present })
    end
    decisions = { 'k.rb:1:11' => present.call(11...17),
                  'k.rb:2:11' => present.call(31...37) }
    decision_paths = {
      'k.rb:1:11' => { ['not nil'] => 3, ['nil'] => 1 },
      'k.rb:2:11' => { ['nil'] => 2 }
    }
    result = PathCoverage::Result.new(decisions, {}, decision_paths)
    expected = {
      'k.rb:1:11' => { ['nil'] => 1 }, 'k.rb:2:11' => { ['nil'] => 2 }
    }
    assert_equal expected, result.outside
  end
end
