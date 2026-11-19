require_relative 'test_helper'
require 'path_coverage/method_ways'

class MethodWaysTest < TidTest
  test 'Mw7a01', %w(
  | Example: ship, an if on express whose arm returns 1, then a
  | ternary on rush
  | Each way one call can take through a method is listed as its
  | steps, as a call's trace records them: a decision's name and
  | path, a return's or raise's name alone. The if true returns,
  | so no way goes on from it to the ternary.
  ) do
    source = <<~RUBY
      def ship(order)
        if order[:express]
          return 1
        end
        order[:rush] ? 2 : 3
      end
    RUBY
    express = 'k.rb:2:2'
    rush = 'k.rb:5:15'
    expected = [
      [[express, [true]], ['k.rb:3:4']],
      [[express, [false]], [rush, [true]]],
      [[express, [false]], [rush, [false]]]
    ]
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal expected.to_set, ways.to_set
  end

  test 'Mw7a02', %w(
  | Example: total's ways as calls take them, its each block
  | holding an if on paid, then a return if the amount is
  | large: on a paid and an unpaid order, the block made 2+
  | passes; on none, 0
  | A call witnesses each way it took, each pass of a block
  | inlined: one way for each distinct way its passes took, a
  | block with no pass adding nothing. Steps are in the order
  | their rows are written, so a way is compared by its steps
  | alone.
  ) do
    block = 'k.rb:3:14'
    paid = [['k.rb:4:4', [true]]]
    unpaid = [['k.rb:4:4', [false]]]
    large = ['k.rb:8:16', [false]]
    two = [large, [block, ['2+ items'], Set[paid, unpaid]]]
    none = [[block, ['0 items'], Set[]], large]
    witnessed = [two, none].map do |way|
      PathCoverage::MethodWays.witnessed(way)
    end
    expected = [
      Set[[*paid, large], [*unpaid, large]],
      Set[[large]]
    ]
    assert_equal expected, witnessed
  end

  test 'Mw7a03', %w(
  | Example: total, an each block whose body holds an if on
  | paid, then amount, its ways listed with loops on
  | With loops on a loop is a fork: no pass, its body in no
  | step, or at least one, its body walked once. The loop steps
  | first, by where it starts, 0 items or 1+ items.
  ) do
    source = <<~RUBY
      def total(orders)
        amount = 0
        orders.each do |order|
          if order[:paid]
            amount += order[:amount]
          end
        end
        amount
      end
    RUBY
    block = 'k.rb:3:14'
    some = [block, ['1+ items']]
    expected = [
      [[block, ['0 items']]],
      [some, ['k.rb:4:4', [true]]],
      [some, ['k.rb:4:4', [false]]]
    ]
    ways = PathCoverage::MethodWays.of(source, 'k.rb', loops: true)
    assert_equal expected.to_set, ways['k.rb:1:0'].to_set
  end

  test 'Mw7a04', %w(
  | Example: first_paid, an each block whose line declares it
  | is never given no items, its body returning 1 if an order is
  | paid, then 0; its ways split with loops on
  | A way giving no items to a loop on a line carrying the
  | comment # path: impossible 0 items is impossible, as no call
  | can take it.
  ) do
    source = <<~RUBY
      def first_paid(orders)
        orders.each do |order| # path: impossible 0 items
          return 1 if order[:paid]
        end
        0
      end
    RUBY
    block = 'k.rb:2:14'
    some = [block, ['1+ items']]
    split = [
      [[some, ['k.rb:3:13', [true]]], [some, ['k.rb:3:13', [false]]]],
      [[[block, ['0 items']]]]
    ]
    ways = PathCoverage::MethodWays.split(source, 'k.rb', loops: true)
    assert_equal split.map(&:to_set), ways['k.rb:1:0'].map(&:to_set)
  end
end
