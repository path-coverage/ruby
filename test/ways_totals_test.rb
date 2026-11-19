require_relative 'test_helper'
require 'path_coverage/ways_totals'

class WaysTotalsTest < TidTest
  WAY = [{ 'at' => '4:08', 'path' => [true] },
         { 'at' => '6:04' }].freeze

  test 'Wt7a01', %w(
  | Example: a report of total, 3 ways, 2 covered, and price,
  | more paths than max_paths 8 allows, beside a top card
  | The totals are read from the report's JSON alone: the ways
  | covered out of every listed method's ways, then how many
  | methods have more paths than max_paths, naming its value. A
  | top card, which no call runs, counts in neither.
  ) do
    report = { 'max_paths' => 8, 'cards' => {
      'lib/a.rb:1:0' => total(2),
      'lib/b.rb:3:0' => { 'name' => 'price', 'ways' => 27,
                          'taken' => [] },
      'lib/b.rb:1:0' => { 'name' => 'B', 'ways' => 2 }
    } }
    assert_equal ['Paths: 2 / 3 (66.67%)',
                  'Functions over --max-paths=8: 1'],
                 PathCoverage::WaysTotals.lines(report)
  end

  test 'Wt7a02', %w(
  | Example: reports of total, 3 ways, 2 covered; total with all
  | 3 covered; no method at all; two methods, all covered; two,
  | one with a gap; and price, more paths than max_paths 8 allows
  | A report with a path no test took fails, as one with a
  | method over max_paths does; one with every path taken does
  | not, nor one with no method.
  ) do
    untested = total(2)
    tested = total(3)
    over = { 'name' => 'price', 'ways' => 27, 'taken' => [] }
    listings = [[untested], [tested], [], [tested, tested],
                [tested, untested], [over]]
    reports = listings.map do |cards|
      listed = cards.each_with_index.to_h do |card, n|
        ["lib/a.rb:#{n + 1}:0", card]
      end
      { 'max_paths' => 8, 'cards' => listed }
    end
    failed = reports.map { PathCoverage::WaysTotals.failed?(_1) }
    assert_equal [true, false, false, false, true, true], failed
  end

  test 'Wt7a03', %w(
  | Example: a report of retry, every possible path taken, but a
  | call took a path its # path: impossible comment declared
  | impossible
  | A report where a call took a path declared impossible fails:
  | the declaration is wrong, and the worklist says to remove it.
  ) do
    retried = total(3).merge('impossible_taken' => [WAY])
    report = { 'max_paths' => 8,
               'cards' => { 'lib/r.rb:2:0' => retried } }
    assert PathCoverage::WaysTotals.failed?(report)
  end

  private

  # A card of total, 3 ways, covered of them taken, the rest gaps.
  def total(covered)
    { 'name' => 'total', 'ways' => 3, 'taken' => [],
      'covered' => [{ 'way' => WAY, 'count' => 1 }] * covered,
      'gaps' => [WAY] * (3 - covered), 'impossible_taken' => [] }
  end
end
