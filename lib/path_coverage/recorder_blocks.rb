require_relative 'condition'

module PathCoverage
  # The part of the recorder that notes block method calls, eg
  # ids.any? { |id| id.odd? }: its block's answers, as the leaf
  # after the receiver's, at; at is 0 for a call that is a decision
  # of its own. The receiver's leaf stays nil, as how many items
  # the block was called with is a loop's question. It relies on
  # its includer's counts, record and trails.
  module RecorderBlocks
    # Starts a block method's call in decision, its receiver the
    # decision's at-th leaf; returns the decision's current trail,
    # nil for none.
    def begin_items(decision, _at)
      trails(decision).last
    end

    # Notes value, the block's answer, as its last, for a call
    # whose receiver is decision's at-th leaf; returns value
    # unchanged. A block called where its call was not entered,
    # eg in another fiber, is counted but noted on no path.
    def item_at(decision, at, value)
      record(decision, at + 1, value)
    end

    # Notes value, the block's answer for one more item, among
    # all its answers so far: all true, all false, or both, for a
    # call whose receiver is decision's at-th leaf; returns value
    # unchanged. A block called where its call was not entered
    # is counted but noted on no path.
    def answer_at(decision, at, value)
      trail = trails(decision).last
      note_answer(trail, at, value) if trail
      @counts[[decision, at + 1]][value ? :truthy : :falsy] += 1
      value
    end

    # Notes on trail value among the answers so far of the block
    # whose receiver is its at-th leaf.
    def note_answer(trail, at, value)
      now = value ? ANSWERS[0] : ANSWERS[1]
      same = [nil, now].include?(trail.outcomes[at + 1])
      trail.outcomes[at + 1] = same ? now : ANSWERS[2]
    end

    # Ends a block method's call whose receiver is decision's at-th
    # leaf, counting the receiver truthy when its block was
    # called, as its answer leaf shows, falsy when not; returns
    # value unchanged. A call whose block was never called
    # leaves trail unwitnessed. With no trail, as begin_items
    # found none, it is counted as called.
    def end_items(decision, at, trail, value)
      called = trail.nil? || !trail.outcomes[at + 1].nil?
      trail.unwitnessed = true unless called
      @counts[[decision, at]][called ? :truthy : :falsy] += 1
      value
    end
  end
end
