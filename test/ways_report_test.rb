require_relative 'test_helper'
require 'path_coverage/ways_report'

class WaysReportTest < TidTest
  test 'Wr7a01', %w(
  | Example: total's call's way, its each block making 2+
  | passes, paid then unpaid, then a return
  | A unit's ways are listed for the JSON report in the order
  | first taken, each with how many took it: a decision's step
  | its row's at and path, a return's its at alone, and a
  | loop's its at, its path, and the distinct ways its passes
  | took, ordered by their JSON text, as a set has no order.
  ) do
    paid = [['k.rb:5:6', [true]]]
    unpaid = [['k.rb:5:6', [false]]]
    loop = ['k.rb:4:16', ['2+ items'], Set[paid, unpaid]]
    way = [loop, ['k.rb:9:4']]
    listed = PathCoverage::WaysReport.taken({ way => 2 })
    passes = [
      [{ 'at' => '5:06', 'path' => [false] }],
      [{ 'at' => '5:06', 'path' => [true] }]
    ]
    expected = [{
      'way' => [
        { 'at' => '4:16', 'path' => ['2+ items'],
          'passes' => passes },
        { 'at' => '9:04' }
      ],
      'count' => 2
    }]
    assert_equal expected, listed
  end

  test 'Wr7a02', %w(
  | Example: a JSON report whose card for total lists its call's
  | way, its each block making 2+ passes, then a return, and the
  | block's passes; and a top card, which lists neither
  | The ways a report's cards list are read back as a call's
  | trace counts them: each method's calls' ways under its
  | entry, each loop's passes' under the loop.
  ) do
    paid = [['k.rb:5:6', [true]]]
    unpaid = [['k.rb:5:6', [false]]]
    block = 'k.rb:4:16'
    way = [[block, ['2+ items'], Set[paid, unpaid]], ['k.rb:9:4']]
    ways = {
      'k.rb:2:2' => { way => 1 },
      block => { paid => 1, unpaid => 1 }
    }
    card = {
      'taken' => PathCoverage::WaysReport.taken(ways['k.rb:2:2']),
      'passes' => { '4:16' => PathCoverage::WaysReport.taken(ways[block]) }
    }
    report = { 'cards' => { 'k.rb:2:2' => card, 'k.rb:0:0' => {} } }
    assert_equal ways, PathCoverage::WaysReport.ways(report)
  end
end
