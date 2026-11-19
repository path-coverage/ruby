require_relative 'test_helper'
require 'path_coverage/loop_forks'
require 'path_coverage/manifest'

class LoopForksTest < TidTest
  test 'Lf7a01', %w(
  | Example: late, an each block over orders holding a while on
  | an order's retry, then whether any order is late
  | Each loop whose passes a pass call can show forks, by its
  | bytes and its body's: the each block and the while; the
  | any? block does not, as its decision's paths count its
  | items already.
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
    expected = {
      'k.rb:1:0' => {
        'k.rb:2:14' => [block, loop],
        'k.rb:3:4' => [loop, wait...(wait + 'order.wait'.size)]
      }
    }
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    forks = PathCoverage::LoopForks.of(source, 'k.rb', decisions)
    assert_equal expected, forks
  end
end
