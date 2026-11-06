require_relative 'decision_paths'

module PathCoverage
  # What a run found: every decision the manifest knows of, with
  # the counts its operands were recorded with. Every
  # reporter builds on this.
  class Result
    NEVER_RAN = { truthy: 0, falsy: 0 }.freeze

    # decisions is { decision => Condition }, from the manifest;
    # counts is { [decision, index] => counts } and decision_paths is
    # { decision => { path => evaluations } }, both from the
    # recorder.
    def initialize(decisions, counts, decision_paths = {})
      @decisions = decisions
      @counts = counts
      @decision_paths = decision_paths
    end

    # { decision => [{ path:, count: }, ...] }: every possible path
    # of each decision, as DecisionPaths gives them, with the
    # number of evaluations that took it, zero for one never
    # taken.
    def paths
      @decisions.to_h do |decision, condition|
        taken = @decision_paths.fetch(decision, {})
        all = DecisionPaths.possible(condition).map do |path|
          { path:, count: taken.fetch(path, 0) }
        end
        [decision, all]
      end
    end

    # { decision => { path => evaluations } } of each path taken
    # that is none of its decision's possible paths, eg a &. receiver
    # nil though treated as present; only decisions with one. Such a
    # path shows a treatment to be wrong, so it is reported, never
    # dropped.
    def outside
      all = @decisions.to_h do |decision, condition|
        taken = @decision_paths.fetch(decision, {})
        [decision, taken.except(*DecisionPaths.possible(condition))]
      end
      all.reject { |_, paths| paths.empty? }
    end

    # The paths taken, as Render.run takes them: decision_paths:,
    # as paths gives them, and outside:.
    def taken
      { decision_paths: paths, outside: }
    end

    # { decision => [counts of operand 0, counts of operand 1, ...] },
    # with zero counts for an operand that never ran, and
    # only: naming the one outcome a fixed leaf can have.
    def operands
      @decisions.to_h do |decision, condition|
        leaves = condition.leaves.each_with_index.map do |range, i|
          leaf(decision, condition, range, i)
        end
        [decision, leaves]
      end
    end

    private

    # The counts of one leaf, with only: when it is fixed.
    def leaf(decision, condition, range, index)
      counts = counts_of(decision, index)
      only = condition.fixed[range]
      only ? counts.merge(only:) : counts
    end

    # The recorded counts of one operand, or zeros.
    def counts_of(decision, index)
      @counts.fetch([decision, index], NEVER_RAN)
    end
  end
end
