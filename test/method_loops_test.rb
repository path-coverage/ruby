require_relative 'test_helper'
require 'path_coverage/method_loops'

class MethodLoopsTest < TidTest
  test 'Mp7q01', %w(
  | Example: total, an each block whose body holds an if on
  | paid, then a return if the amount is positive, then 0
  | Each row of a method, and each block holding a row, is
  | mapped to the blocks holding it, outermost first: the if in
  | the block to the block, the modifier if, the return's row,
  | to none.
  ) do
    source = <<~RUBY
      def total(orders)
        amount = 0
        orders.each do |order|
          if order[:paid]
            amount += order[:amount]
          end
        end
        return amount if amount.positive?
        0
      end
    RUBY
    block = 'k.rb:3:14'
    expected = {
      'k.rb:1:0' => {
        block => [], 'k.rb:4:4' => [block], 'k.rb:8:16' => []
      }
    }
    loops = PathCoverage::MethodLoops.of(source, 'k.rb')
    assert_equal expected, loops
  end

  test 'Mp7q02', %w(
  | Example: fetch_all, a do ... rescue block whose body fetches
  | and returns early if a url is cached, rescuing a timeout to
  | raise when urgent; log_all, an empty block and an each block
  | holding nothing; and noop, an empty def holding a def
  | A pass call goes first in each loop body with a statement:
  | in a do ... rescue block, its first statement before the
  | rescue; in a block holding no row too, as a fork when loops
  | are decisions. An empty block, or a def holding none, has
  | none.
  ) do
    source = <<~RUBY
      def fetch_all(urls)
        urls.each do |url|
          return url if url.cached?
        rescue Timeout::Error
          raise if url.urgent?
        end
      end

      def log_all(lines)
        lines.each { }
        lines.each { |line| puts line }
      end

      def noop
        def inner = nil
      end
    RUBY
    loops = PathCoverage::MethodLoops.of(source, 'k.rb')
    passes = PathCoverage::MethodLoops.passes(source, 'k.rb', loops)
    firsts = {
      'k.rb:2:12' => source.index('return url'),
      'k.rb:11:13' => source.index('puts line')
    }
    assert_equal firsts, passes
  end

  test 'Mp7q03', %w(
  | Example: rescue_all, a do ... rescue block with no statement
  | before its rescue, which raises when a url is urgent
  | A loop whose rows are all in its rescue has no pass call,
  | as no statement there can raise, so its rescue never runs.
  ) do
    source = <<~RUBY
      def rescue_all(urls)
        urls.each do |url|
        rescue Timeout::Error
          raise if url.urgent?
        end
      end
    RUBY
    loops = PathCoverage::MethodLoops.of(source, 'k.rb')
    passes = PathCoverage::MethodLoops.passes(source, 'k.rb', loops)
    assert_equal({}, passes)
  end

  test 'Mp7q04', %w(
  | Example: first_free, an each block over orders holding an
  | each block over each order's items, which returns the first
  | free item, and a check of each order after; and none, an
  | empty def
  | A row in a nested block is held by both blocks, outermost
  | first, the inner block by the outer; each block holding a
  | row has a pass call first in its body; an empty def has no
  | loops.
  ) do
    source = <<~RUBY
      def first_free(orders)
        orders.each do |order|
          order[:items].each do |item|
            return item if item[:free]
          end
          return nil if order[:last]
        end
      end

      def none; end
    RUBY
    outer = 'k.rb:2:14'
    inner = 'k.rb:3:23'
    expected = {
      'k.rb:1:0' => {
        outer => [], inner => [outer],
        'k.rb:4:18' => [outer, inner], 'k.rb:6:15' => [outer]
      },
      'k.rb:10:0' => {}
    }
    loops = PathCoverage::MethodLoops.of(source, 'k.rb')
    passes = PathCoverage::MethodLoops.passes(source, 'k.rb', loops)
    firsts = {
      outer => source.index('order[:items]'),
      inner => source.index('return item')
    }
    assert_equal [expected, firsts], [loops, passes]
  end

  test 'Mp7q05', %w(
  | Example: wait, a modifier while stepping a clock by a ternary
  | on fast while it is busy, then an empty while on idle
  | A modifier loop's body is written before its test, so a call
  | put first in it would run once, not each pass: it holds its
  | rows, but has no pass call. A keyword loop with an empty body
  | holds nothing.
  ) do
    source = <<~RUBY
      def wait(clock)
        clock.step(clock.fast? ? 2 : 1) while clock.busy?
        while clock.idle?; end
      end
    RUBY
    loops = PathCoverage::MethodLoops.of(source, 'k.rb')
    passes = PathCoverage::MethodLoops.passes(source, 'k.rb', loops)
    held = { 'k.rb:2:2' => [], 'k.rb:2:25' => ['k.rb:2:2'] }
    assert_equal [{ 'k.rb:1:0' => held }, {}], [loops, passes]
  end

  test 'Mp7q06', %w(
  | Example: number and again, defs parsing the first of texts,
  | each with a rescue of ArgumentError that retries unless texts
  | are used up; then the same with none, an empty def, and
  | plain, a def with no rescue, between them
  | A def whose own rescue retries restarts its frame on a retry,
  | so it is noted by the line it starts on. A def with no body,
  | or no rescue, is not.
  ) do
    number = <<~RUBY
      def number(texts)
        Integer(texts.shift)
      rescue ArgumentError
        retry unless texts.empty?
        0
      end
    RUBY
    again = number.sub('number', 'again')
    between = "def none; end\ndef plain(text)\n  Integer(text)\nend\n"
    sources = [number + again, number + between + again]
    restarts = sources.map do |source|
      PathCoverage::MethodLoops.restarts(source)
    end
    assert_equal [Set[1, 7], Set[1, 11]], restarts
  end

  test 'Mp7q07', %w(
  | Example: fetch, a def whose begin gets a url, with a rescue
  | holding a begin of its own that logs it, with a rescue that
  | retries; then ship, a def whose begin sends an order, with a
  | rescue holding a plain begin that logs it, then a retry
  | A begin whose rescue retries is a loop. A retry in a begin's
  | own rescue is that begin's, not one holding it. A begin with
  | no rescue takes no retry.
  ) do
    source = <<~RUBY
      def fetch(url)
        begin
          get(url)
        rescue IOError
          begin
            log(url)
          rescue
            retry
          end
        end
      end
      def ship(order)
        begin
          order.send
        rescue IOError
          begin
            order.log
          end
          retry
        end
      end
    RUBY
    defs = PathCoverage::LoopNodes.defs(Prism.parse(source).value)
    loops = defs.flat_map { PathCoverage::LoopNodes.loops_in(_1.body) }
    lines = loops.map { _1.location.start_line }
    assert_equal [5, 13], lines
  end
end
