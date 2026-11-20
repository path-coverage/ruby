require_relative 'test_helper'
require 'path_coverage/walk'

class WalkTest < TidTest
  test 'Wk7a01', %w(
  | Example: fee, an if on member then a return, called once,
  | member true
  | A call's way is its steps in order, each a row's name,
  | with its path for a decision; finishing the call counts
  | that way once, under the call's entry.
  ) do
    ways = {}
    walk = PathCoverage::Walk.new('k.rb:1:0', ways, {})
    walk.step(['k.rb:2:2', [true]])
    walk.step(['k.rb:4:2'])
    walk.finish
    way = [['k.rb:2:2', [true]], ['k.rb:4:2']]
    assert_equal({ 'k.rb:1:0' => { way => 1 } }, ways)
  end

  test 'Wk7a02', %w(
  | Example: total, an each block whose body holds an if on
  | paid, then a return, called once on a paid then an unpaid
  | order
  | Each pass of a loop is a way of its own, counted under the
  | loop; the call's way holds the loop as one step: how many
  | passes it made, 0, 1 or 2+, and the set of ways they took.
  ) do
    ways = {}
    loop = 'k.rb:3:2'
    loops = { loop => [], 'k.rb:4:6' => [loop], 'k.rb:7:2' => [] }
    walk = PathCoverage::Walk.new('k.rb:1:0', ways, loops)
    walk.passed(loop)
    walk.step(['k.rb:4:6', [true]])
    walk.passed(loop)
    walk.step(['k.rb:4:6', [false]])
    walk.exhausted(loop)
    walk.step(['k.rb:7:2'])
    walk.finish
    paid, unpaid = [true, false].map { [['k.rb:4:6', [_1]]] }
    passes = [loop, ['2+ items'], Set[paid, unpaid]]
    expected = {
      loop => { paid => 1, unpaid => 1 },
      'k.rb:1:0' => { [passes, ['k.rb:7:2']] => 1 }
    }
    assert_equal expected, ways
  end

  test 'Wk7a03', %w(
  | Example: total, an each block whose body holds an if on
  | paid, then a return, called on no orders, then on one
  | paid order
  | A loop that made no pass is a step of 0 items with no way
  | taken; one that made a single pass, of 1 item.
  ) do
    ways = {}
    loop = 'k.rb:3:2'
    loops = { loop => [], 'k.rb:4:6' => [loop], 'k.rb:7:2' => [] }
    none = PathCoverage::Walk.new('k.rb:1:0', ways, loops)
    none.exhausted(loop)
    none.step(['k.rb:7:2'])
    none.finish
    one = PathCoverage::Walk.new('k.rb:1:0', ways, loops)
    one.passed(loop)
    one.step(['k.rb:4:6', [true]])
    one.exhausted(loop)
    one.step(['k.rb:7:2'])
    one.finish
    paid = [['k.rb:4:6', [true]]]
    calls = {
      [[loop, ['0 items'], Set[]], ['k.rb:7:2']] => 1,
      [[loop, ['1 item'], Set[paid]], ['k.rb:7:2']] => 1
    }
    assert_equal({ loop => { paid => 1 }, 'k.rb:1:0' => calls }, ways)
  end

  test 'Wk7a04', %w(
  | Example: drain, a while on ready whose body holds an each
  | block over a batch holding an if on urgent; called once,
  | ready, one batch of one urgent item, then ready again
  | A step of a row in a while's test is taken on its first run
  | alone: its later runs, while the while is under way, even
  | with a block inside it under way too, repeat its first.
  ) do
    ways = {}
    test = 'k.rb:2:8'
    urgent = 'k.rb:4:6'
    loops = { 'k.rb:2:2' => [], 'k.rb:3:16' => ['k.rb:2:2'],
              urgent => ['k.rb:2:2', 'k.rb:3:16'], test => [] }
    walk = PathCoverage::Walk.new('k.rb:1:0', ways, loops,
                                  { test => 'k.rb:2:2' })
    walk.step([test, [true]])
    walk.passed('k.rb:2:2')
    walk.passed('k.rb:3:16')
    walk.step([urgent, [true]])
    walk.step([test, [true]])
    walk.finish
    pass = [[urgent, [true]]]
    batch = [['k.rb:3:16', ['1 item'], Set[pass]]]
    call = [[test, [true]], ['k.rb:2:2', ['1 item'], Set[batch]]]
    expected = { 'k.rb:3:16' => { pass => 1 },
                 'k.rb:2:2' => { batch => 1 },
                 'k.rb:1:0' => { call => 1 } }
    assert_equal expected, ways
  end
end
