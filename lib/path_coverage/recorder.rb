require_relative 'call_trace'
require_relative 'condition'
require_relative 'recorder_blocks'
require_relative 'recorder_cases'
require_relative 'recorder_chains'
require_relative 'recorder_writes'

module PathCoverage
  # Records the outcome of each instrumented operand.
  class Recorder
    include RecorderBlocks
    include RecorderCases
    include RecorderChains
    include RecorderWrites

    # One evaluation's way through its decision: the outcome of
    # each leaf, nil for one not yet, or never, reached; and
    # whether it witnesses no path, as when a block method's
    # block was never called.
    Trail = Struct.new(:decision, :outcomes, :unwitnessed)

    # Starts with no outcomes, decision paths or reaches counted.
    def initialize
      @counts = Hash.new do |counts, key|
        counts[key] = { truthy: 0, falsy: 0 }
      end
      @decision_paths = Hash.new do |decision_paths, decision|
        decision_paths[decision] = Hash.new(0)
      end
      @reached = Hash.new(0)
      @trails_key = :"path_coverage_trails_#{object_id}"
      @trace = CallTrace.new
    end

    # { name => runs } of each statement reached so far, by its
    # name, eg { "k.rb:2:2" => 2 }; none never reached.
    attr_reader :reached

    # The ways each call of a covered method has taken so far.
    attr_reader :trace

    # Counts a run of the statement named name, a step of its
    # call's way.
    def reach(name)
      @reached[name] += 1
      @trace.reach(name)
      nil
    end

    # Notes a pass of the loop named name, a block called with
    # one more item.
    def pass(name)
      @trace.pass(name)
      nil
    end

    # Notes that the rescue fork named name completed, as a step
    # of the call under way. Returns value unchanged.
    def completed(name, value)
      @trace.decided(name, ['completed'])
      value
    end

    # Notes that the rescue numbered number of the rescue fork
    # named name ran, as a step of the call under way.
    def rescued(name, number)
      @trace.decided(name, ["rescue #{number}"])
      nil
    end

    # The stack of decision's evaluations under way in the current
    # thread (fiber), innermost last, so another thread's never
    # mix with its.
    def trails(decision)
      stacks = Thread.current[@trails_key] ||=
        Hash.new { |all, key| all[key] = [] }
      stacks[decision]
    end

    # { decision => { [outcome, ...] => evaluations } } for every
    # evaluation of a decision entered and left so far.
    attr_reader :decision_paths

    # Starts an evaluation of decision, which has size leaves, as
    # the trail its leaves' records fill in.
    def enter(decision, size)
      trail = Trail.new(decision, Array.new(size))
      trails(decision).push(trail)
      trail
    end

    # Ends trail's evaluation, counting its path, and returns
    # value, the decision's, unchanged. An evaluation of the same
    # decision still entered above trail, as one that raised
    # leaves, took trail's later outcomes, so trail's path is
    # not counted; the stack is cleared down to trail either
    # way. An unwitnessed trail's path is not counted either.
    # A counted path is a step of its call's way.
    def leave(trail, value)
      stack = trails(trail.decision)
      clean = stack.last.equal?(trail)
      nil until stack.empty? || stack.pop.equal?(trail)
      decided(trail) if clean && !trail.unwitnessed
      value
    end

    # Counts trail's path, its decision's, and steps its call's
    # way with it.
    def decided(trail)
      @decision_paths[trail.decision][trail.outcomes] += 1
      @trace.decided(trail.decision, trail.outcomes)
    end

    # The truthy and falsy counts of every operand recorded so
    # far, keyed by [decision, index]; an operand that never ran
    # has no entry.
    attr_reader :counts

    # Counts value's outcome and returns it unchanged, so the
    # condition around it behaves exactly as uninstrumented.
    def record(decision, index, value)
      outcome = value ? :truthy : :falsy
      @counts[[decision, index]][outcome] += 1
      trail = trails(decision).last
      trail.outcomes[index] = outcome == :truthy if trail
      value
    end

    # A stand-in for a case's index-th pattern of total: the
    # case matches its subject against the stand-in, which
    # matches it against the pattern, once, as the case would
    # have.
    WhenMatch = Struct.new(
      :recorder, :decision, :index, :total, :pattern
    ) do
      # Whether pattern matches subject, exactly as pattern says,
      # noted on the decision's path.
      def ===(subject)
        recorder.matched(decision, index, total, pattern === subject)
      end
    end

    # The stand-in for pattern, the index-th of size in the case
    # at decision.
    def when_match(decision, index, size, pattern)
      WhenMatch.new(self, decision, index, size, pattern)
    end

    # Notes whether the index-th of size patterns matched, the
    # first entering the case's decision, and a match or the last
    # leaving it, as no more patterns are then tried; returns
    # matched unchanged.
    def matched(decision, index, size, matched)
      enter(decision, size) if index.zero?
      record(decision, index, matched)
      last = matched || index == size - 1
      leave(trails(decision).last, matched) if last
      matched
    end
  end
end
