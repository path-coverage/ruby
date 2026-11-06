require_relative 'test_helper'
require 'path_coverage/merge'

class MergeTest < TidTest
  test 'Mg8q10', %w(
  | the operands of several runs merge by adding each
  | operand's true and false counts, keeping a fixed
  | leaf's only, so a gap one run left another can close
  ) do
    first = {
      'source/kata.rb:3:23' => [
        { truthy: 2, falsy: 0 },
        { truthy: 1, falsy: 1 }
      ],
      'source/clock.rb:2:11' => [
        { truthy: 0, falsy: 1 },
        { truthy: 1, falsy: 0, only: :truthy }
      ]
    }
    second = {
      'source/kata.rb:3:23' => [
        { truthy: 0, falsy: 3 },
        { truthy: 0, falsy: 0 }
      ],
      'source/clock.rb:2:11' => [
        { truthy: 4, falsy: 0 },
        { truthy: 0, falsy: 0, only: :truthy }
      ]
    }
    expected = {
      'source/kata.rb:3:23' => [
        { truthy: 2, falsy: 3 },
        { truthy: 1, falsy: 1 }
      ],
      'source/clock.rb:2:11' => [
        { truthy: 4, falsy: 1 },
        { truthy: 1, falsy: 0, only: :truthy }
      ]
    }
    actual = PathCoverage::Merge.operands([first, second])
    assert_equal expected, actual
  end

  test 'Mg8q20', %w(
  | the decision paths of several runs merge by adding each
  | path's counts, so a path one run never took another can
  ) do
    first = {
      'source/kata.rb:3:23' => [
        { path: [true, true], count: 2 },
        { path: [true, false], count: 0 },
        { path: [false, nil], count: 0 }
      ]
    }
    second = {
      'source/kata.rb:3:23' => [
        { path: [true, true], count: 0 },
        { path: [true, false], count: 1 },
        { path: [false, nil], count: 0 }
      ]
    }
    expected = {
      'source/kata.rb:3:23' => [
        { path: [true, true], count: 2 },
        { path: [true, false], count: 1 },
        { path: [false, nil], count: 0 }
      ]
    }
    actual = PathCoverage::Merge.paths([first, second])
    assert_equal expected, actual
  end

  test 'Mg8q21', %w(
  | the decision paths of runs that list a decision's paths
  | differently, eg one with select's impossible paths cut, do
  | not merge, as
  | adding counts by position would credit one path's count to
  | another
  ) do
    first = {
      'source/kata.rb:4:9' => [
        { path: ['0 items'], count: 1 },
        { path: ['1 item'], count: 0 },
        { path: ['2+ items'], count: 3 }
      ]
    }
    second = {
      'source/kata.rb:4:9' => [
        { path: ['0 items'], count: 2 },
        { path: ['2+ items'], count: 0 }
      ]
    }
    error = assert_raises(ArgumentError) do
      PathCoverage::Merge.paths([first, second])
    end
    assert_equal 'runs differ at source/kata.rb:4:9', error.message
  end
end
