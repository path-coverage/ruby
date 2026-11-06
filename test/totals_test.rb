require_relative 'test_helper'
require 'path_coverage/totals'

class TotalsTest < TidTest
  test 'Tq7m10', %w(
  | Example: ok?(id) && new?(id) taken by 2 paths of its 3,
  | and ok?(id) ? :ok : :no taken by both of its 2
  | The alone total is [taken, possible] over every site.
  | So it is [4, 5].
  | It counts the same paths the gap lines list as never taken.
  ) do
    site_paths = {
      'source/kata.rb:3:23' => [
        { path: [true, true], count: 2 },
        { path: [true, false], count: 0 },
        { path: [false, nil], count: 1 }
      ],
      'source/kata.rb:7:4' => [
        { path: [true], count: 3 },
        { path: [false], count: 1 }
      ]
    }
    assert_equal [4, 5], PathCoverage::Totals.alone(site_paths)
  end

  test 'Tq7m20', %w(
  | Example: fee, its card 4 of its 6 paths taken, and price,
  | 17 of its 21
  | The combined total is [taken, possible] over every method's
  | card, its size its possible paths.
  | So it is [21, 27].
  ) do
    cards = {
      'source/fee.rb:2:2' => [4, 6], 'source/shop.rb:18:2' => [17, 21]
    }
    assert_equal [21, 27], PathCoverage::Totals.combined(cards)
  end

  test 'Tq7m30', %w(
  | Example: a file with no def
  | It has no cards, so its combined total is [0, 0].
  ) do
    assert_equal [0, 0], PathCoverage::Totals.combined({})
  end
end
