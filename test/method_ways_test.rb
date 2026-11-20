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

  test 'Mw7a05', %w(
  | Example: price, a def whose body parses text as an Integer,
  | with a rescue of ArgumentError giving 0
  | A rescue forks the method, at the rescue: its body completes,
  | or the rescue runs. Each is a way, its step the fork's name
  | and its path: completed, or the rescue's number among its
  | rescues.
  ) do
    source = <<~RUBY
      def price(text)
        Integer(text)
      rescue ArgumentError
        0
      end
    RUBY
    rescued = 'k.rb:3:0'
    expected = [
      [[rescued, ['completed']]],
      [[rescued, ['rescue 1']]]
    ]
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal expected.to_set, ways.to_set
  end

  test 'Mw7a06', %w(
  | Example: flush, a def whose body writes a buffer, with an
  | ensure closing it
  | An ensure runs on every way out, so it forks nothing: a body
  | with an ensure and no rescue has the one way of its body.
  ) do
    source = <<~RUBY
      def flush(buffer)
        buffer.write
      ensure
        buffer.close
      end
    RUBY
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal [[]], ways
  end

  test 'Mw7a07', %w(
  | Example: price, a def returning 0 for empty text, else
  | parsing it as an Integer, with a rescue of ArgumentError
  | giving -1
  | Its rescue can run from anywhere in its body, after any of
  | its rows: so each prefix of each way of its body, cut at a
  | row, then the rescue, is a way; a way that has left the
  | method, here by the return, runs no rescue.
  ) do
    source = <<~RUBY
      def price(text)
        if text.empty?
          return 0
        end
        Integer(text)
      rescue ArgumentError
        -1
      end
    RUBY
    empty = 'k.rb:2:2'
    rescued = 'k.rb:6:0'
    expected = [
      [[empty, [true]], ['k.rb:3:4']],
      [[empty, [false]], [rescued, ['completed']]],
      [[rescued, ['rescue 1']]],
      [[empty, [true]], [rescued, ['rescue 1']]],
      [[empty, [false]], [rescued, ['rescue 1']]]
    ]
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal expected.to_set, ways.to_set
  end

  test 'Mw7a08', %w(
  | Example: led?, an || of an any? and xs.empty?, with a rescue
  | of TypeError giving false
  | A decision and the decisions in its condition, here the ||
  | and its any?, are cut whole: a prefix holds all of them or
  | none. So each way of the body, as it is without the rescue,
  | completes or runs the rescue, and so does none of it.
  ) do
    body = <<~RUBY
      def led?(xs)
        xs.any? { |x| x.odd? } || xs.empty?
    RUBY
    source = "#{body}rescue TypeError\n  false\nend\n"
    unrescued = "#{body}end\n"
    rescued = 'k.rb:3:0'
    whole = PathCoverage::MethodWays.of(unrescued, 'k.rb')['k.rb:1:0']
    completed = whole.map { [*_1, [rescued, ['completed']]] }
    ran = [[], *whole].map { [*_1, [rescued, ['rescue 1']]] }
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal (completed + ran).to_set, ways.to_set
  end

  test 'Mw7a09', %w(
  | Example: ship, a def whose if on paid holds an if on rush that
  | sends it express, with a rescue of IOError retrying later
  | A cut can fall inside an arm: after the if on paid is true,
  | before its if on rush has run. Inside an arm there is no cut
  | after a row's last step, as that is the cut after the row.
  ) do
    source = <<~RUBY
      def ship(order)
        if order.paid?
          if order.rush?
            order.express
          end
        end
      rescue IOError
        order.retry_later
      end
    RUBY
    paid = 'k.rb:2:2'
    rush = 'k.rb:3:4'
    body = [
      [[paid, [true]], [rush, [true]]],
      [[paid, [true]], [rush, [false]]],
      [[paid, [false]]]
    ]
    rescued = 'k.rb:7:0'
    completed = body.map { [*_1, [rescued, ['completed']]] }
    prefixes = [[], [[paid, [true]]], *body]
    ran = prefixes.map { [*_1, [rescued, ['rescue 1']]] }
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal (completed + ran).to_set, ways.to_set
  end

  test 'Mw7a10', %w(
  | Example: total, a def summing the price of each paid order in
  | an each block, with a rescue of TypeError giving 0; loops are
  | decisions
  | A cut can fall inside a loop's body: after at least one item,
  | before the if on paid in it has run.
  ) do
    source = <<~RUBY
      def total(orders)
        sum = 0
        orders.each do |order|
          sum += order.price if order.paid?
        end
        sum
      rescue TypeError
        0
      end
    RUBY
    loop = 'k.rb:3:14'
    paid = 'k.rb:4:23'
    some = [loop, ['1+ items']]
    body = [
      [[loop, ['0 items']]],
      [some, [paid, [true]]],
      [some, [paid, [false]]]
    ]
    rescued = 'k.rb:7:0'
    completed = body.map { [*_1, [rescued, ['completed']]] }
    prefixes = [[], [some], *body]
    ran = prefixes.map { [*_1, [rescued, ['rescue 1']]] }
    ways = PathCoverage::MethodWays.of(source, 'k.rb', loops: true)
    assert_equal (completed + ran).to_set, ways['k.rb:1:0'].to_set
  end

  test 'Mw7a11', %w(
  | Example: price, a def parsing text as an Integer, with a
  | rescue of ArgumentError giving 0, then one of TypeError
  | giving -1
  | Each rescue is a path of the fork, numbered in the order
  | written, the fork named where the first rescue is.
  ) do
    source = <<~RUBY
      def price(text)
        Integer(text)
      rescue ArgumentError
        0
      rescue TypeError
        -1
      end
    RUBY
    rescued = 'k.rb:3:0'
    expected = [
      [[rescued, ['completed']]],
      [[rescued, ['rescue 1']]],
      [[rescued, ['rescue 2']]]
    ]
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal expected.to_set, ways.to_set
  end

  test 'Mw7a12', %w(
  | Example: ship, a def raising IOError if the order is lost,
  | else sending it, with a rescue of IOError retrying later
  | A raise written in a body with a rescue is taken as caught
  | there: its ways are prefixes of the rescue, never ways that
  | leave the method, so none is a gap no call can take.
  ) do
    source = <<~RUBY
      def ship(order)
        raise IOError if order.lost?
        order.send_now
      rescue IOError
        order.retry_later
      end
    RUBY
    lost = 'k.rb:2:16'
    rescued = 'k.rb:4:0'
    expected = [
      [[lost, [false]], [rescued, ['completed']]],
      [[rescued, ['rescue 1']]],
      [[lost, [false]], [rescued, ['rescue 1']]],
      [[lost, [true]], [rescued, ['rescue 1']]]
    ]
    ways = PathCoverage::MethodWays.of(source, 'k.rb')['k.rb:1:0']
    assert_equal expected.to_set, ways.to_set
  end
end
