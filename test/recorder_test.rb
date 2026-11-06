require_relative 'test_helper'
require 'path_coverage/recorder'

class RecorderTest < TidTest
  test '8TuB10', %w(
  | recording an operand returns its value unchanged,
  | so the && it sits in still short-circuits
  | and still yields the same result
  ) do
    recorder = PathCoverage::Recorder.new
    kata = { 'id' => 'Kp9sA2' }
    assert_same kata, recorder.record('k.rb:2:2', 0, kata)
    assert_nil recorder.record('k.rb:2:2', 1, nil)
  end

  test '8TuB20', %w(
  | each operand's truthy and falsy outcomes are counted,
  | keyed by its decision and index
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:2'
    # ok?(id) && new?(id), called three times
    recorder.record(decision, 0, true)
    recorder.record(decision, 1, true)
    recorder.record(decision, 0, true)
    recorder.record(decision, 1, false)
    recorder.record(decision, 0, nil) # so new?(id) never runs
    expected = {
      [decision, 0] => { truthy: 2, falsy: 1 },
      [decision, 1] => { truthy: 1, falsy: 1 }
    }
    assert_equal expected, recorder.counts
  end

  test '8TuB50', %w(
  | each evaluation of a decision, entered before its first leaf
  | and left after its last, counts its path: the outcome of
  | each leaf it reached, nil for one it never did; leaving
  | returns the decision's value unchanged
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:2'
    # ok?(id) && new?(id), called twice
    trail = recorder.enter(decision, 2)
    recorder.record(decision, 0, true)
    recorder.record(decision, 1, false)
    assert_same false, recorder.leave(trail, false)
    trail = recorder.enter(decision, 2)
    recorder.record(decision, 0, nil)
    assert_nil recorder.leave(trail, nil)
    expected = { decision => { [true, false] => 1,
                               [false, nil] => 1 } }
    assert_equal expected, recorder.decision_paths
  end

  test '8TuB51', %w(
  | an evaluation of a decision in another thread, while one is
  | under way, fills in a trail of its own, so neither
  | thread's path takes the other's outcomes
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:2'
    # ok?(id) && new?(id), in two threads at once
    entered = Queue.new
    resume = Queue.new
    trail = recorder.enter(decision, 2)
    recorder.record(decision, 0, true)
    other = Thread.new do
      mine = recorder.enter(decision, 2)
      recorder.record(decision, 0, false)
      entered.push(:entered)
      resume.pop
      recorder.leave(mine, false)
    end
    entered.pop
    recorder.record(decision, 1, true)
    resume.push(:resume)
    other.join
    recorder.leave(trail, true)
    expected = { decision => { [false, nil] => 1,
                               [true, true] => 1 } }
    assert_equal expected, recorder.decision_paths
  end

  test '8TuB52', %w(
  | an evaluation left while one of the same site it called
  | is still entered, eg after that one raised, counts no
  | path, since its later outcomes went to the other; so no
  | path is ever claimed as seen that was not, and the stack
  | is cleared down to it
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:2'
    # ok?(id) || retry?(id), whose retry? recursed and raised
    outer = recorder.enter(decision, 2)
    recorder.record(decision, 0, false)
    recorder.enter(decision, 2)
    recorder.record(decision, 1, true)
    assert_same true, recorder.leave(outer, true)
    assert_equal({}, recorder.decision_paths)

    trail = recorder.enter(decision, 2)
    recorder.record(decision, 0, true)
    recorder.leave(trail, true)
    expected = { decision => { [true, nil] => 1 } }
    assert_equal expected, recorder.decision_paths
  end

  test '8TuB53', %w(
  | an evaluation left in a fiber other than the one that
  | entered it is not on that fiber's stack, so it counts
  | no path, and leaving it still returns
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:2'
    trail = Fiber.new do
      recorder.enter(decision, 2).tap do
        recorder.record(decision, 0, true)
      end
    end.resume
    assert_same :ok, recorder.leave(trail, :ok)
    assert_equal({}, recorder.decision_paths)
  end

  test '8TuB60', %w(
  | Example: case x when 1, 2 then :small when String then :text
  | else :other end
  | Each pattern, eg 1, is replaced by a stand-in.
  | Matching x against a stand-in matches x against its
  | pattern, once.
  | The stand-in records whether it matched.
  | The first pattern (1) enters the decision.
  | A match, or the last pattern (String), leaves it.
  | So each evaluation's path is counted.
  | Eg 1 matches the first pattern, so no later one is tried.
  | The case still picks the same arm, eg :small for 2.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:2'
    stand = lambda do |index, pattern|
      recorder.when_match(decision, index, 3, pattern)
    end
    kind = lambda do |x|
      case x
      when stand.call(0, 1), stand.call(1, 2) then :small
      when stand.call(2, String) then :text
      else :other
      end
    end
    kinds = [1, 2, 'Kp', :k].map { |x| kind.call(x) }
    assert_equal %i[small small text other], kinds
    expected = {
      decision => {
        [true, nil, nil] => 1,
        [false, true, nil] => 1, [false, false, true] => 1,
        [false, false, false] => 1
      }
    }
    assert_equal expected, recorder.decision_paths
  end

  test '8TuB61', %w(
  | Example: ids.any? { |id| ok.include?(id) }, with no ids, one
  | id ok or not, and two ids, neither ok or the second
  | The call is entered before it runs.
  | It is left after it returns.
  | Each of the block's answers is noted on the way.
  | The path is how many ids the block was called with, and
  | its last answer, eg ['1 item', true].
  | The call's result and the block's answers are unchanged.
  | The receiver (ids) counts truthy when the block was called.
  | It counts falsy when the block was not called.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:6'
    any = lambda do |ids, ok|
      trail = recorder.enter(decision, 2)
      begun = recorder.begin_items(decision, 0)
      found = ids.any? do |id|
        recorder.item_at(decision, 0, ok.include?(id))
      end
      recorder.leave(trail,
                     recorder.end_items(decision, 0, begun, found))
    end
    calls = [
      [[], []], [[:a], [:a]], [[:a], []], [%i[a b], []],
      [%i[a b], [:b]]
    ]
    founds = calls.map { |ids, ok| any.call(ids, ok) }
    assert_equal [false, true, false, false, true], founds
    expected = {
      decision => {
        ['0 items', nil] => 1, ['1 item', true] => 1,
        ['1 item', false] => 1, ['2+ items', false] => 1,
        ['2+ items', true] => 1
      }
    }
    assert_equal expected, recorder.decision_paths
    counts = {
      [decision, 0] => { truthy: 4, falsy: 1 },
      [decision, 1] => { truthy: 2, falsy: 4 }
    }
    assert_equal counts, recorder.counts
  end

  test '8TuB62', %w(
  | Example: any? entered in one fiber, its block run in another
  | The block's answer (:ok) is counted.
  | It is returned unchanged.
  | It is not noted on any path.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:6'
    trail = recorder.enter(decision, 2)
    begun = recorder.begin_items(decision, 0)
    answer = Fiber.new { recorder.item_at(decision, 0, :ok) }.resume
    assert_same :ok, answer
    recorder.leave(trail,
                   recorder.end_items(decision, 0, begun, false))
    expected = { decision => { ['0 items', nil] => 1 } }
    assert_equal expected, recorder.decision_paths
    assert_equal({ truthy: 1, falsy: 0 },
                 recorder.counts[[decision, 1]])
  end

  test '8TuB63', %w(
  | Example: ids.select { |id| id.odd? }, with no ids, one id odd
  | or not, and two ids, both odd, both even or one each
  | select calls its block with every item.
  | Each answer is noted.
  | The path is how many ids, and whether the answers were
  | all true, all false, or both.
  | Eg [1, 2] gives ['2+ items', 'both'].
  | The call's result and the block's answers are unchanged.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:6'
    select = lambda do |ids|
      trail = recorder.enter(decision, 2)
      begun = recorder.begin_items(decision, 0)
      kept = ids.select do |id|
        recorder.answer_at(decision, 0, id.odd?)
      end
      recorder.leave(trail,
                     recorder.end_items(decision, 0, begun, kept))
    end
    idss = [[], [1], [2], [1, 3], [2, 4], [1, 2]]
    kept = idss.map { |ids| select.call(ids) }
    assert_equal [[], [1], [], [1, 3], [], [1]], kept
    expected = {
      decision => {
        ['0 items', nil] => 1, ['1 item', 'all true'] => 1,
        ['1 item', 'all false'] => 1, ['2+ items', 'all true'] => 1,
        ['2+ items', 'all false'] => 1, ['2+ items', 'both'] => 1
      }
    }
    assert_equal expected, recorder.decision_paths
    assert_equal({ truthy: 4, falsy: 4 },
                 recorder.counts[[decision, 1]])
  end

  test '8TuB64', %w(
  | Example: select entered in one fiber, its block run in
  | another
  | The block's answer (nil) is counted.
  | It is returned unchanged.
  | It is not noted on any path.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:6'
    trail = recorder.enter(decision, 2)
    begun = recorder.begin_items(decision, 0)
    answer = Fiber.new { recorder.answer_at(decision, 0, nil) }.resume
    assert_nil answer
    recorder.leave(trail, recorder.end_items(decision, 0, begun, []))
    expected = { decision => { ['0 items', nil] => 1 } }
    assert_equal expected, recorder.decision_paths
    assert_equal({ truthy: 0, falsy: 1 },
                 recorder.counts[[decision, 1]])
  end

  test '8TuB67', %w(
  | Example: ok && ids.any? { |id| id.odd? }, the any? begun in
  | another fiber than its decision was entered in
  | There is no trail to begin its items on.
  | So it begins none, and the decision's path is unchanged.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:4'
    trail = recorder.enter(decision, 3)
    begun = Fiber.new { recorder.begin_items(decision, 1) }.resume
    assert_nil begun
    recorder.leave(trail, true)
    expected = { decision => { [nil, nil, nil] => 1 } }
    assert_equal expected, recorder.decision_paths
  end

  test '8TuB66', %w(
  | Example: user&.name entered in one fiber, its receiver user
  | noted in another
  | user is counted, not nil.
  | It is returned unchanged.
  | It is not noted on any path.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:4'
    trail = recorder.enter(decision, 1)
    user = Struct.new(:name).new('kim')
    noted = Fiber.new do
      recorder.present(decision, 0, 0, user)
    end.resume
    assert_same user, noted
    recorder.leave(trail, 'kim')
    assert_equal({ decision => { [nil] => 1 } },
                 recorder.decision_paths)
    assert_equal({ truthy: 1, falsy: 0 },
                 recorder.counts[[decision, 0]])
  end

  test '8TuB70', %w(
  | Example: a write reached twice, a value once
  | Each reach of a statement is counted, by its name.
  | A statement never reached has no count.
  ) do
    recorder = PathCoverage::Recorder.new
    recorder.reach('k.rb:2:2')
    recorder.reach('k.rb:3:2')
    recorder.reach('k.rb:2:2')
    expected = { 'k.rb:2:2' => 2, 'k.rb:3:2' => 1 }
    assert_equal expected, recorder.reached
  end

  test '8TuB71', %w(
  | Example: ok && ids.any? { |id| id.odd? }, the any? begun in
  | another fiber than its decision was entered in, then ended
  | There is no trail its items were begun on.
  | So its receiver is counted as called, truthy.
  | Its value is returned unchanged.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:2:4'
    trail = recorder.enter(decision, 3)
    begun = Fiber.new { recorder.begin_items(decision, 1) }.resume
    ended = recorder.end_items(decision, 1, begun, true)
    recorder.leave(trail, ended)
    assert_equal true, ended
    assert_equal({ truthy: 1, falsy: 0 },
                 recorder.counts[[decision, 1]])
  end

  test '8TuB72', %w(
  | Example: @port ||= 8080 settled in a fiber where its decision
  | was never entered
  | There is no trail to have noted its target's outcome.
  | So the outcome skipped is noted, here truthy, as @port
  | was already set.
  | The write's value is returned unchanged.
  ) do
    recorder = PathCoverage::Recorder.new
    decision = 'k.rb:3:4'
    settling = Fiber.new { recorder.settle(decision, 0, true, 8080) }
    settled = settling.resume
    assert_equal 8080, settled
    assert_equal({ truthy: 1, falsy: 0 },
                 recorder.counts[[decision, 0]])
  end
end
