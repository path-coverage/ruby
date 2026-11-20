require_relative 'test_helper'
require 'path_coverage/rescue_forks'

class RescueForksTest < TidTest
  test 'Rf7a01', %w(
  | Example: TIMEOUT, a constant parsed with a rescue modifier
  | outside any def; then ship, a def sending an order with a
  | rescue modifier giving nil, then raising IOError with a
  | rescue modifier retrying later
  | A rescue modifier in a def is a fork of it. One outside every
  | def is not. Its rescue's value is wrapped where it runs. Its
  | expression is wrapped where it completes, unless it leaves, as
  | a raise does, when it never completes.
  ) do
    source = <<~RUBY
      TIMEOUT = Integer(ENV['TIMEOUT']) rescue 30
      def ship(order)
        order.send_now rescue nil
        raise IOError rescue order.retry_later
      end
    RUBY
    found = PathCoverage::RescueForks.found(source, 'k.rb')
    sent = 'k.rb:3:17'
    raised = 'k.rb:4:16'
    actual = [found.forks.keys, found.forks['k.rb:2:0'].keys,
              found.completions.keys, found.values.keys]
    expected = [['k.rb:2:0'], [sent, raised], [sent], [sent, raised]]
    assert_equal expected, actual
  end
end
