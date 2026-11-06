module PathCoverage
  # Combines the operands of several runs of the same source.
  module Merge
    # One operands hash, as Result#operands gives them, whose
    # counts are the sums of every run's.
    def self.operands(runs)
      runs.reduce do |total, run|
        total.merge(run) do |_decision, mine, theirs|
          mine.zip(theirs).map { |a, b| sum(a, b) }
        end
      end
    end

    # One decision paths hash, as Result#paths gives them, each
    # path's count the sum of every run's. Runs that list a
    # decision's paths differently raise, as adding their counts by
    # position would credit one path's count to another.
    def self.paths(runs)
      runs.reduce do |total, run|
        total.merge(run) do |name, mine, theirs|
          same = mine.map { _1[:path] } == theirs.map { _1[:path] }
          raise ArgumentError, "runs differ at #{name}" unless same

          mine.zip(theirs).map do |a, b|
            { path: a[:path], count: a[:count] + b[:count] }
          end
        end
      end
    end

    # One listed hash, { decision => { path => count } }, eg the
    # paths a treatment rules out, each path's count the sum of
    # every run's, eg [true, false] taken once in each of two
    # runs is taken twice.
    def self.listed(runs)
      runs.reduce do |total, run|
        total.merge(run) do |_decision, mine, theirs|
          mine.merge(theirs) { |_path, a, b| a + b }
        end
      end
    end

    # One operand's counts from two runs, added; a fixed leaf's
    # only comes from the source, so either run's will do.
    def self.sum(mine, theirs)
      mine.merge(theirs) do |key, a, b|
        key == :only ? a : a + b
      end
    end
  end
end
