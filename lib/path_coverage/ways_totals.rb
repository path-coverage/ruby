require_relative 'console_summary'

module PathCoverage
  # The terminal totals of a JSON report, read from its JSON alone,
  # so a person reads what an AI reading the same JSON finds: the
  # ways covered, and the methods with more paths than max paths
  # allows.
  module WaysTotals
    # True when report, a JSON report as a Hash, fails: a method in
    # it has a path no test took, a path taken that was declared
    # impossible, or more paths than its max_paths.
    def self.failed?(report)
      listed, over = methods(report)
      untaken = listed.sum do |card|
        card['gaps'].size + card['impossible_taken'].size
      end
      !over.empty? || untaken.positive?
    end

    # The totals lines of report, a JSON report as a Hash: its
    # listed methods' ways covered out of their ways, then how many
    # methods have more paths than its max_paths, each such one
    # failing.
    def self.lines(report)
      listed, over = methods(report)
      covered = listed.sum { _1['covered'].size }
      ways = listed.sum { _1['ways'] }
      limit = report['max_paths']
      ["Paths: #{ConsoleSummary.figure([covered, ways])}",
       "Functions over --max-paths=#{limit}: #{over.size}"]
    end

    # [listed, over] of report's method cards: those listing their
    # ways, and those with more paths than its max_paths, which
    # list none. A top card, run by no call, has no taken ways, so
    # is in neither.
    def self.methods(report)
      found = report['cards'].values.group_by do |card|
        next :top unless card.key?('taken')

        card.key?('covered') ? :listed : :over
      end
      [found.fetch(:listed, []), found.fetch(:over, [])]
    end
  end
end
