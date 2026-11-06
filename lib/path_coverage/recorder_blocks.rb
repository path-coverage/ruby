require_relative 'condition'

module PathCoverage
  # The part of the recorder that notes block method calls, eg
  # ids.any? { |id| id.odd? }: how many items the block was called
  # with, as the receiver's leaf, at, and its answers, as the next
  # leaf; at is 0 for a call that is a decision of its own. It relies
  # on its includer's counts, record and trails.
  module RecorderBlocks
    # Starts a block method's call in decision, its receiver the
    # decision's at-th leaf, its block not yet called with any item;
    # returns the decision's current trail, nil for none.
    def begin_items(decision, at)
      trail = trails(decision).last
      trail.outcomes[at] = ITEMS[0] if trail
      trail
    end

    # Notes value, the block's answer, as its last, and one more
    # item it was called with, for a call whose receiver is
    # decision's at-th leaf; returns value unchanged. A block called
    # where its call was not entered, eg in another fiber, is
    # counted but noted on no path.
    def item_at(decision, at, value)
      trail = trails(decision).last
      one_more(trail, at) if trail
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

    # Notes on trail one more item, and value among the answers
    # so far of the block whose receiver is its at-th leaf.
    def note_answer(trail, at, value)
      one_more(trail, at)
      now = value ? ANSWERS[0] : ANSWERS[1]
      same = [nil, now].include?(trail.outcomes[at + 1])
      trail.outcomes[at + 1] = same ? now : ANSWERS[2]
    end

    # Notes on trail one more item the block whose receiver is its
    # at-th leaf was called with.
    def one_more(trail, at)
      called = ITEMS.index(trail.outcomes[at]) + 1
      trail.outcomes[at] = ITEMS[[called, 2].min]
    end

    # Ends a block method's call whose receiver is decision's at-th
    # leaf, counting the receiver truthy when its block was
    # called, falsy when not; returns value unchanged. With no
    # trail, as begin_items found none, it is counted as called.
    def end_items(decision, at, trail, value)
      called = trail.nil? || trail.outcomes[at] != ITEMS[0]
      @counts[[decision, at]][called ? :truthy : :falsy] += 1
      value
    end
  end
end
