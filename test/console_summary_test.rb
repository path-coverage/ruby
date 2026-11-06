require_relative 'test_helper'
require 'path_coverage/console_summary'

class ConsoleSummaryTest < TidTest
  test 'Cs4m10', %w(
  | Example: lib/kata.rb's decision taking 2 of its 3 paths, and
  | test/kata_test.rb's taking 1 of its 2, with groups code and
  | test
  | Each group is a heading, its own totals indented under it.
  | There is no total over every group.
  | With no cards given, as methods are not measured, there is no
  | combined line.
  ) do
    decision_paths = {
      'lib/kata.rb:3:4' => [
        { path: [true, true], count: 2 },
        { path: [true, false], count: 1 },
        { path: [false, nil], count: 0 }
      ],
      'test/kata_test.rb:9:6' => [
        { path: [true], count: 4 },
        { path: [false], count: 0 }
      ]
    }
    groups = { 'code' => ['lib/**/*.rb'], 'test' => ['test/**/*.rb'] }
    expected = [
      'code:',
      '  Paths alone: 2 / 3 (66.67%)',
      'test:',
      '  Paths alone: 1 / 2 (50.00%)'
    ]
    summary = PathCoverage::ConsoleSummary
    actual = summary.lines(decision_paths, nil, groups)
    assert_equal expected, actual
  end

  test 'Cs4m20', %w(
  | Example: fee in lib/fee.rb, its card 4 of its 6 paths
  | taken, and groups code and test
  | Each group has a combined line too: code has fee's 4 / 6.
  | test, with no def, has 0 / 0, shown as -.
  ) do
    cards = { 'lib/fee.rb:1:0' => [4, 6] }
    groups = { 'code' => ['lib/**/*.rb'], 'test' => ['test/**/*.rb'] }
    summary = PathCoverage::ConsoleSummary
    lines = summary.lines({}, cards, groups)
    expected = [
      'code:',
      '  Paths alone: 0 / 0 (-)',
      '  Paths combined: 4 / 6 (66.67%)',
      'test:',
      '  Paths alone: 0 / 0 (-)',
      '  Paths combined: 0 / 0 (-)'
    ]
    assert_equal expected, lines
  end

  test 'Cs4m30', %w(
  | Example: two decisions, both in lib/, with groups code and test
  | code totals both decisions' paths; test totals none.
  ) do
    two = { path: [true], count: 1 }
    decision_paths = {
      'lib/a.rb:1:0' => [two], 'lib/b.rb:1:0' => [two]
    }
    groups = { 'code' => ['lib/**/*.rb'], 'test' => ['test/**/*.rb'] }
    summary = PathCoverage::ConsoleSummary
    actual = summary.group_totals(decision_paths, nil, groups)
    expected = {
      'code' => { 'alone' => [2, 2] },
      'test' => { 'alone' => [0, 0] }
    }
    assert_equal expected, actual
  end
end
