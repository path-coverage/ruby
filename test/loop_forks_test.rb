require_relative 'test_helper'
require 'path_coverage/loop_forks'

class LoopForksTest < TidTest
  test 'Lf7a01', %w(
  | Example: late, an each block over orders holding a while on
  | an order's retry, then whether any order is late
  | Each loop whose passes a pass call can show forks, by its
  | bytes and its body's: the each block, the while, and the
  | any? block, as its decision's paths are its answers alone,
  | leaving how many items it was called with to its loop.
  ) do
    source = <<~RUBY
      def late(orders)
        orders.each do |order|
          while order.retry?
            order.wait
          end
        end
        orders.any? { |order| order.late? }
      end
    RUBY
    ends = source.index("  end\n  orders") + 5
    block = source.index('do |order|')...ends
    loop = source.index('while')...(source.index("    end\n") + 7)
    wait = source.index('order.wait')
    any = source.index('{')...(source.index('}') + 1)
    late = source.index('order.late?')
    expected = {
      'k.rb:1:0' => {
        'k.rb:2:14' => [block, loop],
        'k.rb:3:4' => [loop, wait...(wait + 'order.wait'.size)],
        'k.rb:7:14' => [any, late...(late + 'order.late?'.size)]
      }
    }
    forks = PathCoverage::LoopForks.of(source, 'k.rb')
    assert_equal expected, forks
  end
end
