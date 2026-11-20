require_relative 'test_helper'
require 'path_coverage/call_trace'

class CallTraceTest < TidTest
  test 'Ct7r01', %w(
  | Example: total, an if on rush, then a call of price, whose
  | value is a ternary on vip; total called once, rush and vip
  | Each call's steps go to the way of that call alone, though
  | one call runs inside another: price's ternary is a step of
  | price's way, not total's, and each way is counted as its
  | call returns.
  ) do
    trace = PathCoverage::CallTrace.new
    total = 'k.rb:2:2'
    price = 'k.rb:7:2'
    trace.know(total, { 'k.rb:3:4' => [] })
    trace.know(price, { 'k.rb:8:4' => [] })
    trace.call
    trace.reach(total)
    trace.decided('k.rb:3:4', [true])
    trace.call
    trace.reach(price)
    trace.decided('k.rb:8:4', [true])
    trace.return
    trace.return
    expected = {
      total => { [['k.rb:3:4', [true]]] => 1 },
      price => { [['k.rb:8:4', [true]]] => 1 }
    }
    assert_equal expected, trace.ways
  end

  test 'Ct7r02', %w(
  | Example: depth, an each block over children whose body holds
  | a return if a child is a leaf, else a recursive call; called
  | on a node with one leaf child
  | A row reached, eg a return, is a step too, and each pass of
  | a block a pass of its loop; a recursive call's steps go to
  | the innermost call, so each call's way is its own.
  ) do
    trace = PathCoverage::CallTrace.new
    depth = 'k.rb:1:0'
    block = 'k.rb:2:2'
    leaf = 'k.rb:3:4'
    leave = 'k.rb:4:6'
    trace.know(depth,
               { block => [], leaf => [block], leave => [block] })
    run_depth(trace, depth, block, leaf, leave)
    inner = [[leaf, [true]], [leave]]
    outer = [[leaf, [false]]]
    expected = {
      block => { inner => 1, outer => 1 },
      depth => {
        [[block, ['1 item'], Set[inner]]] => 1,
        [[block, ['1 item'], Set[outer]]] => 1
      }
    }
    assert_equal expected, trace.ways
  end

  test 'Ct7r03', %w(
  | Example: ship, an if on express, its entry reached by a call
  | that began before the trace did; then a decision, a row and a
  | pass of no method known
  | Events with no call under way to take them, or of rows no
  | known method holds, take no step and count no way.
  ) do
    trace = PathCoverage::CallTrace.new
    trace.know('k.rb:1:0', { 'k.rb:2:2' => [] })
    trace.reach('k.rb:1:0')
    trace.decided('k.rb:2:2', [true])
    trace.call
    trace.decided('k.rb:9:2', [true])
    trace.reach('k.rb:9:4')
    trace.pass('k.rb:9:6')
    trace.return
    assert_equal({}, trace.ways)
  end

  test 'Ct7r04', %w(
  | Example: total, a block of its own given to each_order, a
  | covered method of an orders object, whose block holds an if
  | on paid; called once, on a paid order
  | A step of total's block, run while each_order's call is the
  | innermost under way, goes to total's call, the innermost of
  | the method holding it; one of no known method goes nowhere.
  ) do
    trace = PathCoverage::CallTrace.new
    total = 'k.rb:1:0'
    each_order = 'k.rb:8:2'
    block = 'k.rb:2:20'
    paid = 'k.rb:3:4'
    trace.know(total, { block => [], paid => [block] })
    trace.know(each_order, { 'k.rb:9:4' => [] })
    trace.call
    trace.reach(total)
    trace.call
    trace.reach(each_order)
    trace.pass(block)
    trace.decided(paid, [true])
    trace.decided('k.rb:20:2', [false])
    trace.return
    trace.return
    expected = {
      each_order => { [] => 1 },
      block => { [[paid, [true]]] => 1 },
      total => { [[block, ['1 item'], Set[[[paid, [true]]]]]] => 1 }
    }
    assert_equal expected, trace.ways
  end

  test 'Ct7r05', %w(
  | Example: total, which returns a lambda holding an if on paid;
  | later, which calls that lambda after total has returned
  | A step of a method with no call of its own under way, eg of a
  | lambda it made, run while another method's call is the only
  | one under way, goes nowhere: neither call's way takes it.
  ) do
    trace = PathCoverage::CallTrace.new
    total = 'k.rb:1:0'
    later = 'k.rb:8:0'
    paid = 'k.rb:3:4'
    trace.know(total, { paid => [] })
    trace.know(later, { 'k.rb:9:2' => [] })
    trace.call
    trace.reach(total)
    trace.return
    trace.call
    trace.reach(later)
    trace.decided(paid, [true])
    trace.return
    expected = { total => { [] => 1 }, later => { [] => 1 } }
    assert_equal expected, trace.ways
  end

  private

  # Runs depth on a node with one leaf child, as trace sees it:
  # the outer call's pass taking leaf false, then the recursive
  # call's taking it true and returning.
  def run_depth(trace, depth, block, leaf, leave)
    [
      [:call], [:reach, depth], [:pass, block],
      [:decided, leaf, [false]],
      [:call], [:reach, depth], [:pass, block],
      [:decided, leaf, [true]],
      [:reach, leave], [:return], [:return]
    ].each { |event| trace.public_send(*event) }
  end
end
