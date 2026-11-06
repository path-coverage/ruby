# The calls rewritten code makes, each handed to the kernel's
# one recorder. Like the kernel, this file loads before any
# covered file and is never itself instrumented.
module PathCoverage
  # The call rewritten code makes around each operand; returns
  # value unchanged.
  def self.record(decision, index, value)
    @recorder.record(decision, index, value)
  end

  # The call rewritten code makes before a decision's first leaf,
  # decision having size leaves; returns the evaluation's trail.
  def self.enter(decision, size)
    @recorder.enter(decision, size)
  end

  # The call rewritten code makes around a decision as a whole,
  # with the trail enter gave it; returns value unchanged.
  def self.leave(trail, value)
    @recorder.leave(trail, value)
  end

  # The call rewritten code makes around a case's pattern, the
  # index-th of size at decision; returns the pattern's stand-in.
  def self.when_match(decision, index, size, pattern)
    @recorder.when_match(decision, index, size, pattern)
  end

  # The call rewritten code makes around the pattern of a case
  # nested in decision, the decision's index-th leaf; returns the
  # pattern's stand-in.
  def self.pattern(decision, index, pattern)
    @recorder.pattern(decision, index, pattern)
  end

  # The call rewritten code makes around the right side of a
  # write nested in decision, its target the decision's at-th leaf,
  # outcome being the target's when it runs; returns value
  # unchanged.
  def self.written_at(decision, at, outcome, value)
    @recorder.written_at(decision, at, outcome, value)
  end

  # The call rewritten code makes around a write nested in decision,
  # its target the decision's at-th leaf, skipped being the target's
  # outcome when its right side never ran; returns value
  # unchanged.
  def self.settle(decision, at, skipped, value)
    @recorder.settle(decision, at, skipped, value)
  end

  # The call rewritten code makes before a block method's call
  # nested in decision runs, its receiver the decision's at-th leaf;
  # returns the decision's trail.
  def self.begin_items(decision, at)
    @recorder.begin_items(decision, at)
  end

  # The call rewritten code makes around the block's expression
  # of a stop-early block method nested in decision, its receiver the
  # decision's at-th leaf; returns value unchanged.
  def self.item_at(decision, at, value)
    @recorder.item_at(decision, at, value)
  end

  # The call rewritten code makes around the block's expression
  # of an every-item block method nested in decision, its receiver
  # the decision's at-th leaf; returns value unchanged.
  def self.answer_at(decision, at, value)
    @recorder.answer_at(decision, at, value)
  end

  # The call rewritten code makes around a block method's call
  # nested in decision, its receiver the decision's at-th leaf,
  # with the trail begin_items gave it; returns value unchanged.
  def self.end_items(decision, at, trail, value)
    @recorder.end_items(decision, at, trail, value)
  end

  # The call rewritten code makes around a &. receiver, the
  # index-th leaf of decision, its chain's leaves starting at first;
  # returns value unchanged.
  def self.present(decision, index, first, value)
    @recorder.present(decision, index, first, value)
  end

  # The call rewritten code makes around a &. chain's value, the
  # index-th leaf of decision, its chain's leaves starting at first;
  # returns value unchanged.
  def self.chained(decision, index, first, value)
    @recorder.chained(decision, index, first, value)
  end

  # The call rewritten code makes before each statement that is
  # no decision, counting its run.
  def self.reach(name)
    @recorder.reach(name)
  end
end
