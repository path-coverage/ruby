require_relative 'test_helper'
require 'path_coverage/paths_report'

class PathsReportTest < TidTest
  test 'Pr7q10', %w(
  | the paths report gives each decision its leaves' spans, as
  | line:column pairs, beside each path and its count, so a
  | tool reading the JSON can recover each leaf exactly
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id)
      end
    RUBY
    decision = condition('&&', 16...23, 27...35)
    decisions = { 'k.rb:2:2' => decision }
    files = { '/app/k.rb' => { source:, decisions: } }
    taken = [
      { path: [true, true], count: 1 },
      { path: [true, false], count: 0 },
      { path: [false, nil], count: 2 }
    ]
    expected = {
      'k.rb:2:2' => {
        leaves: [%w(2:2 2:9), %w(2:13 2:21)], taken:
      }
    }
    report = PathCoverage::PathsReport
    assert_equal expected, report.of({ 'k.rb:2:2' => taken }, files)
  end

  test 'Pr7q20', %w(
  | each decision's leaf texts are cut from its file's source,
  | for the gap lines to name
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id)
      end
    RUBY
    decision = condition('&&', 16...23, 27...35)
    decisions = { 'k.rb:2:2' => decision }
    files = { '/app/k.rb' => { source:, decisions: } }
    expected = { 'k.rb:2:2' => ['ok?(id)', 'new?(id)'] }
    assert_equal expected, PathCoverage::PathsReport.texts(files)
  end
end
