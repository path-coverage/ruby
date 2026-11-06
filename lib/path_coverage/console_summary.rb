require_relative 'summary'
require_relative 'totals'

module PathCoverage
  # The :summary reporter's lines: each total as SimpleCov prints
  # its line and branch coverage, eg
  # "Paths alone: 519 / 623 (83.31%)". With
  # groups configured each group is a heading, its own totals
  # indented under it, and there is no total over every group.
  module ConsoleSummary
    # The summary lines of site_paths and, when cards, { def
    # site => [taken, size] }, are given, as they are when
    # methods are measured, of cards; groups is { name =>
    # [glob, ...] }.
    def self.lines(site_paths, cards, groups = {})
      return totals_lines(totals(site_paths, cards)) if groups.empty?

      all = group_totals(site_paths, cards, groups)
      all.flat_map do |name, totals|
        ["#{name}:", *totals_lines(totals).map { |line| "  #{line}" }]
      end
    end

    # { 'alone' => [taken, possible] } of site_paths, with
    # 'combined' => [taken, possible] of cards when given.
    def self.totals(site_paths, cards)
      totals = { 'alone' => Totals.alone(site_paths) }
      return totals if cards.nil?

      totals.merge('combined' => Totals.combined(cards))
    end

    # { group name => totals } of each group's own sites and
    # cards alone.
    def self.group_totals(site_paths, cards, groups)
      groups.to_h do |name, globs|
        own_cards = cards ? own(cards, globs) : nil
        [name, totals(own(site_paths, globs), own_cards)]
      end
    end

    # The entries of sites, keyed by site name, in a file matching
    # any of globs.
    def self.own(sites, globs)
      sites.select do |site, _|
        Summary.matches?(Summary.path_of(site), globs)
      end
    end

    # The line naming the operators ignored, eg "Path coverage
    # ignores: &&="; none when none are.
    def self.ignored_lines(ignored)
      return [] if ignored.empty?

      ["Path coverage ignores: #{ignored.join(', ')}"]
    end

    # A line per total, eg "Paths combined: 1 / 4 (25.00%)".
    def self.totals_lines(totals)
      totals.map do |name, pair|
        "Paths #{name}: #{figure(pair)}"
      end
    end

    # [taken, possible] as "taken / possible (percent)", its
    # percent to two places, or - when no path is possible.
    def self.figure((taken, possible))
      return "#{taken} / #{possible} (-)" if possible.zero?

      percent = format('%.2f%%', 100.0 * taken / possible)
      "#{taken} / #{possible} (#{percent})"
    end
  end
end
