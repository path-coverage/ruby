require_relative 'test_helper'
require 'path_coverage/runs_report'
require 'fileutils'

class RunsReportTest < TidTest
  serial!

  TOTAL = <<~RUBY.freeze
    module Orders
      def self.total(orders)
        amount = 0
        orders.each do |order|
          if order[:paid]
            amount += order[:amount]
          end
        end
        amount
      end
    end
  RUBY

  test 'Rr7a01', %w(
  | Example: path_coverage_report ROOT '*.rb' OUT RUN, of a saved
  | run of total, an each block whose body holds an if on paid,
  | on a paid and an unpaid order
  | The command reports the saved runs into OUT and prints its
  | totals, read from the JSON it wrote, even when no way is
  | untested, exiting 0.
  ) do |t|
    run = saved_run(t, [{ paid: true, amount: 3 },
                        { paid: false, amount: 4 }])
    status = nil
    expected = "Paths: 2 / 2 (100.00%)\n" \
               "Functions over --max-paths=4096: 0\n"
    assert_output(expected) do
      status = report(t, [t.dir, '*.rb', "#{t.dir}/out", run])
    end
    assert_equal 0, status
  end

  test 'Rr7a02', %w(
  | Example: path_coverage_report --max-paths 1 ROOT '*.rb' OUT
  | RUN, of a saved run of total on a paid order, its 2 ways
  | more than 1
  | A method with more paths than --max-paths fails: it is
  | named, with what to do, before the totals, and the command
  | exits 1.
  ) do |t|
    run = saved_run(t, [{ paid: true, amount: 3 }])
    status = nil
    expected = [
      'orders.rb:2 total() has 2 paths, more than ' \
      '--max-paths allows.',
      'Split it into smaller functions.',
      'Paths: 0 / 0 (-)',
      'Functions over --max-paths=1: 1'
    ].map { "#{_1}\n" }.join
    assert_output(expected) do
      args = ['--max-paths', '1', t.dir, '*.rb', "#{t.dir}/out", run]
      status = report(t, args)
    end
    assert_equal 1, status
  end

  test 'Rr7a03', %w(
  | Example: path_coverage_report -h
  | It prints its usage, with an example, and exits 0.
  ) do
    expected = <<~HELP
      Usage: path_coverage_report [--loops] [--max-paths N] SOURCE_ROOT GLOBS REPORT_DIR RUN_JSON...

      Reports the saved runs RUN_JSON... as one, writing the report into
      REPORT_DIR, then prints each method's untested paths and the totals.
      Exits 0 when every path is taken, and 1 when any is not.

        SOURCE_ROOT  the directory holding the covered source
        GLOBS        comma-separated globs of the covered files, relative to SOURCE_ROOT
        REPORT_DIR   the directory it writes its report into
        RUN_JSON...  one or more saved runs' JSON files, space-separated

      Options:
        -h             Show this help
        --loops        Count each loop as a decision: 0 items or 1+ items
        --max-paths N  Fail each method with more than N paths
                       (default 4096, at most 65536)

      Example:
        path_coverage_report --max-paths 8 /app 'lib/**/*.rb' report runs/*.json
    HELP
    status = nil
    assert_output(expected) do
      status = PathCoverage::RunsReport.main(['-h'])
    end
    assert_equal 0, status
  end

  test 'Rr7a04', %w(
  | Example: path_coverage_report --loops --max-paths 8 /app
  | lib/*.rb out run.json
  | The leading options are read in any order, the rest kept as
  | the root, globs, report dir and runs; the configuration they
  | give counts each loop as a decision, and fails each method
  | with more than 8 paths.
  ) do
    args = %w(--loops --max-paths 8 /app lib/*.rb out run.json)
    options, rest = PathCoverage::RunsReport.options(args)
    config = PathCoverage::RunsReport.configured('/app', 'lib/*.rb',
                                                 'out', options)
    assert_equal [{ loops: true, max_paths: 8 },
                  %w(/app lib/*.rb out run.json), true, 8],
                 [options, rest, config.loops?, config.path_limit]
  end

  test 'Rr7a05', %w(
  | Example: path_coverage_report --loops ROOT '*.rb' OUT RUN, of
  | a saved run of total on a paid and an unpaid order
  | With --loops each loop is a decision: total's each block
  | given 0 items is a path no call took, so the command names
  | it, prints totals of 2 paths of 3, and exits 1.
  ) do |t|
    run = saved_run(t, [{ paid: true, amount: 3 },
                        { paid: false, amount: 4 }])
    status = nil
    expected = [
      'orders.rb:2 total() has 1 untested path.',
      'Add tests that take each of these paths:',
      '  1. line 4 loop: 0 items',
      'Paths: 2 / 3 (66.67%)',
      'Functions over --max-paths=4096: 0'
    ].map { "#{_1}\n" }.join
    assert_output(expected) do
      args = ['--loops', t.dir, '*.rb', "#{t.dir}/out", run]
      status = report(t, args)
    end
    assert_equal 1, status
  end

  private

  # The JSON report of a run of total, written in t's dir, called
  # once on orders, saved beside it.
  def saved_run(fixture, orders)
    fixture.write(TOTAL, 'orders.rb')
    fixture.start
    fixture.load('orders.rb')::Orders.total(orders)
    fixture.report
    saved = "#{fixture.dir}/run.json"
    FileUtils.cp("#{fixture.dir}/path_coverage.json", saved)
    saved
  end

  # The exit status of path_coverage_report run on args, with no
  # orders.rb path_coverage.json left in fixture's dir to mislead.
  def report(fixture, args)
    FileUtils.rm_f("#{fixture.dir}/path_coverage.json")
    PathCoverage::RunsReport.main(args)
  end
end
