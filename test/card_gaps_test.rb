require_relative 'test_helper'
require 'path_coverage/card_gaps'

class CardGapsTest < TidTest
  ROWS = [
    { 'at' => '8:04', 'decision' => 'source/fee.rb:8:4' },
    { 'at' => '8:19', 'decision' => 'source/fee.rb:8:19' },
    { 'at' => '10:04', 'decision' => 'source/fee.rb:10:4' },
    { 'at' => '12:04', 'decision' => nil }
  ].freeze
  TEXTS = {
    'source/fee.rb:8:4' => ['user.member && order.paid'],
    'source/fee.rb:8:19' => ['user.member', 'order.paid'],
    'source/fee.rb:10:4' => ['order.big']
  }.freeze
  PARENTS = { 'source/fee.rb:8:19' => 'source/fee.rb:8:4' }.freeze

  test 'Cg7a01', %w(
  | Example: fee, an if on an &&, then an if on order.big, its
  | card with 4 of its paths untested; a copy with 1; price, a
  | method with more paths than max_paths allows; and a top card
  | One heading for each method, its name with (), then each
  | untested path as a numbered line of its choices, in order,
  | each leaf by its text. An if whose test is an && repeats
  | the &&'s choice, so only the && is named; a step with no
  | choice, eg a return, is left out; one untested path says
  | path. A method with more paths than max_paths allows is
  | named with what to do. A top card, which no call runs, has
  | no lines.
  ) do
    cards = {
      'source/fee.rb:5:0' => card(gaps_of_fee),
      'source/fee_copy.rb:5:0' => card([gaps_of_fee.last]),
      'source/price.rb:5:0' => { 'name' => 'price', 'rows' => ROWS,
                                 'ways' => 6912, 'taken' => [] },
      'source/fee.rb:1:0' => { 'name' => 'Fee', 'rows' => ROWS,
                               'ways' => 6 }
    }
    never = '`user.member` false, then line 10 `order.big` true'
    expected = [
      'source/fee.rb:5 fee() has 4 untested paths.',
      'Add tests that take each of these paths:',
      '  1. line 8 `user.member` true, `order.paid` true, ' \
      'then line 10 `order.big` false',
      '  2. line 8 `user.member` true, `order.paid` false, ' \
      'then line 10 `order.big` true',
      '  3. line 8 `user.member` true, `order.paid` false, ' \
      'then line 10 `order.big` false',
      "  4. line 8 #{never}",
      'source/fee_copy.rb:5 fee() has 1 untested path.',
      'Add tests that take each of these paths:',
      "  1. line 8 #{never}",
      'source/price.rb:5 price() has 6912 paths, more than ' \
      '--max-paths allows.',
      'Split it into smaller functions.'
    ]
    lines = PathCoverage::CardGaps.lines(cards, TEXTS, PARENTS)
    assert_equal expected, lines
  end

  test 'Cg7a02', %w(
  | Example: retry, a loop over a constant of backoffs whose line
  | ends # path: impossible 0 items, measured with loops, called
  | once with the constant empty
  | A method whose call took a path a comment declares
  | impossible is named, with the instruction to remove the
  | comment, then each such path, a loop's step by its line and
  | how many items it ran.
  ) do
    rows = [{ 'at' => '5:04', 'decision' => nil }]
    taken = [[{ 'at' => '3:04', 'path' => ['0 items'] },
              { 'at' => '5:04' }]]
    cards = {
      'lib/retry.rb:2:0' => {
        'name' => 'retry', 'rows' => rows, 'ways' => 2, 'taken' => [],
        'gaps' => [], 'impossible_taken' => taken
      }
    }
    expected = [
      'lib/retry.rb:2 retry() took 1 path declared impossible.',
      'Remove the # path: impossible comment that declares it:',
      '  1. line 3 loop: 0 items'
    ]
    assert_equal expected, PathCoverage::CardGaps.lines(cards, {}, {})
  end

  private

  # A card of fee listing gaps as its untested paths.
  def card(gaps)
    { 'name' => 'fee', 'rows' => ROWS, 'ways' => 6, 'taken' => [],
      'gaps' => gaps, 'impossible_taken' => [] }
  end

  # fee's 4 untested paths, each its steps as a card lists them.
  def gaps_of_fee
    [
      [[true, true], [true], [false]],
      [[true, false], [false], [true]],
      [[true, false], [false], [false]],
      [[false, nil], [false], [true]]
    ].map do |leaves, outer, big|
      [{ 'at' => '8:19', 'path' => leaves },
       { 'at' => '8:04', 'path' => outer },
       { 'at' => '10:04', 'path' => big }, { 'at' => '12:04' }]
    end
  end
end
