require_relative 'test_helper'
require_relative 'coverage_metrics_check'

class CoverageMetricsCheckTest < TidTest
  test 'p0Kj10', %w(
  | a missed count above its max is a breach
  | naming the metric, its value and its range
  ) do
    report = {
      'code' => {
        'lines' => { 'total' => 22, 'missed' => 2 },
        'branches' => { 'total' => 0, 'missed' => 0 }
      }
    }
    bounds = {
      'code' => {
        'lines' => {
          'total' => { 'min' => 1, 'max' => 22 },
          'missed' => { 'min' => 0, 'max' => 0 }
        },
        'branches' => {
          'total' => { 'min' => 0, 'max' => 0 },
          'missed' => { 'min' => 0, 'max' => 0 }
        }
      }
    }
    expected = ['code.lines.missed: 2 is outside 0..0']
    actual = CoverageMetricsCheck.breaches(report, bounds)
    assert_equal expected, actual
  end

  test 'p0Kj70', %w(
  | Example: SimpleCov's report of groups code and test, and
  | path_coverage's totals of the same groups
  | Each group is a heading, its four figures indented under it:
  | lines and branches covered of all, as SimpleCov prints them,
  | then paths alone and combined.
  | Each percent is to two places; none possible shows -.
  ) do
    report = {
      'code' => {
        'lines' => { 'total' => 1221, 'missed' => 0 },
        'branches' => { 'total' => 309, 'missed' => 0 }
      },
      'test' => {
        'lines' => { 'total' => 2220, 'missed' => 2 },
        'branches' => { 'total' => 41, 'missed' => 1 }
      }
    }
    paths = {
      'code' => { 'alone' => [475, 561], 'combined' => [41, 49] },
      'test' => { 'alone' => [63, 86], 'combined' => [0, 0] }
    }
    expected = [
      'code:',
      '  Line coverage: 1221 / 1221 (100.00%)',
      '  Branch coverage: 309 / 309 (100.00%)',
      '  Paths alone: 475 / 561 (84.67%)',
      '  Paths combined: 41 / 49 (83.67%)',
      'test:',
      '  Line coverage: 2218 / 2220 (99.91%)',
      '  Branch coverage: 40 / 41 (97.56%)',
      '  Paths alone: 63 / 86 (73.26%)',
      '  Paths combined: 0 / 0 (-)'
    ]
    actual = CoverageMetricsCheck.groups(report, paths)
    assert_equal expected, actual
  end

  test 'p0Kj80', %w(
  | Example: SimpleCov's report of group test, and path_coverage's
  | test totals of alone [65, 84] and combined [3, 3]
  | Each total joins the group's metrics under paths, in the
  | shape SimpleCov's metrics have: its total, and how many were
  | missed.
  | So a bound such as test.paths.combined.missed 0..0 can gate
  | it.
  ) do
    lines = { 'total' => 2250, 'missed' => 0 }
    report = { 'test' => { 'lines' => lines } }
    totals = { 'alone' => [65, 84], 'combined' => [3, 3] }
    paths = { 'test' => totals }
    expected = {
      'test' => {
        'lines' => lines,
        'paths' => {
          'alone' => { 'total' => 84, 'missed' => 19 },
          'combined' => { 'total' => 3, 'missed' => 0 }
        }
      }
    }
    actual = CoverageMetricsCheck.with_paths(report, paths)
    assert_equal expected, actual
  end

  test 'p0Kj81', %w(
  | Example: a bound test.paths.combined.missed 0..0, and a test
  | method path never taken
  | The breach names it, as any other bound's does.
  ) do
    lines = { 'total' => 9, 'missed' => 0 }
    report = { 'test' => { 'lines' => lines } }
    paths = { 'test' => { 'combined' => [2, 3] } }
    none = { 'missed' => { 'min' => 0, 'max' => 0 } }
    bounds = { 'test' => { 'paths' => { 'combined' => none } } }
    merged = CoverageMetricsCheck.with_paths(report, paths)
    expected = ['test.paths.combined.missed: 1 is outside 0..0']
    actual = CoverageMetricsCheck.breaches(merged, bounds)
    assert_equal expected, actual
  end

  test 'p0Kj82', %w(
  | Example: a group code with no path totals
  | Its metrics are left as they are, with no paths.
  ) do
    lines = { 'total' => 9, 'missed' => 0 }
    report = { 'code' => { 'lines' => lines } }
    actual = CoverageMetricsCheck.with_paths(report, {})
    assert_equal({ 'code' => { 'lines' => lines } }, actual)
  end

  test 'p0Kj71', %w(
  | Example: a report whose group code has lines but no branches,
  | and no path totals
  | The group shows only the figures it has.
  ) do
    lines = { 'total' => 33, 'missed' => 0 }
    report = { 'code' => { 'lines' => lines } }
    expected = ['code:', '  Line coverage: 33 / 33 (100.00%)']
    assert_equal expected, CoverageMetricsCheck.groups(report)
  end

  test 'p0Kj60', %w(
  | Example: code.lines.missed 1 and code.branches.missed 1, the
  | report naming where each was missed
  | Each breach of a missed bound is followed by one line per
  | place missed, so a run that misses one only now and then
  | says which there and then.
  ) do
    report = {
      'code' => {
        'lines' => {
          'total' => 22, 'missed' => 1,
          'where' => ['lib/path_coverage/collector.rb:17']
        },
        'branches' => {
          'total' => 4, 'missed' => 1,
          'where' => ['lib/path_coverage/summary.rb:54 then']
        }
      }
    }
    missed = { 'missed' => { 'min' => 0, 'max' => 0 } }
    bounds = { 'code' => { 'lines' => missed, 'branches' => missed } }
    expected = [
      'code.lines.missed: 1 is outside 0..0',
      '  missed: lib/path_coverage/collector.rb:17',
      'code.branches.missed: 1 is outside 0..0',
      '  missed: lib/path_coverage/summary.rb:54 then'
    ]
    actual = CoverageMetricsCheck.breaches(report, bounds)
    assert_equal expected, actual
  end

  test 'p0Kj20', %w(
  | a total below its min is a breach, so an all-zeros report
  | from a run that loaded no code cannot pass
  ) do
    report = {
      'test' => {
        'lines' => { 'total' => 0, 'missed' => 0 },
        'branches' => { 'total' => 0, 'missed' => 0 }
      }
    }
    bounds = {
      'test' => {
        'lines' => {
          'total' => { 'min' => 1, 'max' => 111 },
          'missed' => { 'min' => 0, 'max' => 0 }
        },
        'branches' => {
          'total' => { 'min' => 1, 'max' => 16 },
          'missed' => { 'min' => 0, 'max' => 0 }
        }
      }
    }
    expected = [
      'test.lines.total: 0 is outside 1..111',
      'test.branches.total: 0 is outside 1..16'
    ]
    actual = CoverageMetricsCheck.breaches(report, bounds)
    assert_equal expected, actual
  end

  test 'p0Kj30', %w(
  | a bounded metric absent from the report is a breach
  | saying so, rather than passing unchecked
  ) do
    report = {
      'code' => {
        'lines' => { 'total' => 22, 'missed' => 0 }
      }
    }
    bounds = {
      'code' => {
        'lines' => {
          'total' => { 'min' => 1, 'max' => 22 },
          'missed' => { 'min' => 0, 'max' => 0 }
        },
        'branches' => {
          'total' => { 'min' => 0, 'max' => 0 }
        }
      }
    }
    expected = ['code.branches.total: missing from the report']
    actual = CoverageMetricsCheck.breaches(report, bounds)
    assert_equal expected, actual
  end

  test 'p0Kj40', %w(
  | a bound naming only its min is a breach saying so,
  | since applying the one side it has would half check it
  ) do
    report = {
      'code' => {
        'lines' => { 'total' => 22, 'missed' => 0 }
      }
    }
    bounds = {
      'code' => {
        'lines' => {
          'total' => { 'min' => 1, 'max' => 22 },
          'missed' => { 'min' => 0 }
        }
      }
    }
    expected = ['code.lines.missed: bound names min but no max']
    actual = CoverageMetricsCheck.breaches(report, bounds)
    assert_equal expected, actual
  end

  test 'p0Kj50', %w(
  | a bound naming only its max is a breach saying so,
  | since an all-zeros report would satisfy it
  ) do
    report = {
      'code' => {
        'lines' => { 'total' => 22, 'missed' => 0 }
      }
    }
    bounds = {
      'code' => {
        'lines' => {
          'total' => { 'max' => 22 },
          'missed' => { 'min' => 0, 'max' => 0 }
        }
      }
    }
    expected = ['code.lines.total: bound names max but no min']
    actual = CoverageMetricsCheck.breaches(report, bounds)
    assert_equal expected, actual
  end
end
