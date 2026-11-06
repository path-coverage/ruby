# Judges a coverage report against min..max bounds.
module CoverageMetricsCheck
  # Returns one line per metric in bounds whose value in report
  # is out of range, eg "code.lines.missed: 2 is outside 0..0";
  # empty when every bound is met.
  def self.breaches(report, bounds, path = [])
    if bound?(bounds)
      breach(report, bounds, path)
    else
      bounds.flat_map do |name, inner|
        breaches(report, inner, path + [name])
      end
    end
  end

  # The names SimpleCov's metrics and path_coverage's totals
  # print under, in the order they print.
  SIMPLECOV = { 'lines' => 'Line', 'branches' => 'Branch' }.freeze
  PATHS = %w(alone combined).freeze

  # Each group of report as a heading, its figures indented under
  # it: SimpleCov's lines and branches covered of all, then the
  # paths taken of all possible that paths, { group => { measure
  # => [taken, possible] } }, has for it, eg
  # "  Line coverage: 1221 / 1221 (100.00%)". A group shows only
  # the figures it has.
  def self.groups(report, paths = {})
    report.flat_map do |name, metrics|
      ["#{name}:", *simplecov_lines(metrics),
       *path_lines(paths.fetch(name, {}))]
    end
  end

  # The line and branch coverage lines of one group's metrics.
  def self.simplecov_lines(metrics)
    SIMPLECOV.filter_map do |metric, label|
      next unless metrics.key?(metric)

      total = metrics[metric]['total']
      covered = total - metrics[metric]['missed']
      "  #{label} coverage: #{figure(covered, total)}"
    end
  end

  # The path coverage lines of one group's totals.
  def self.path_lines(totals)
    PATHS.filter_map do |measure|
      next unless totals.key?(measure)

      taken, possible = totals[measure]
      "  Paths #{measure}: #{figure(taken, possible)}"
    end
  end

  # part / whole (percent), its percent to two places, or - when
  # whole is zero.
  def self.figure(part, whole)
    return "#{part} / #{whole} (-)" if whole.zero?

    percent = format('%.2f%%', 100.0 * part / whole)
    "#{part} / #{whole} (#{percent})"
  end

  # report with each group's path totals in paths, { group => {
  # measure => [taken, possible] } }, joined to its metrics under
  # 'paths', in the shape its other metrics have, eg
  # { 'combined' => { 'total' => 3, 'missed' => 0 } }, so bounds
  # can gate them as they gate lines and branches.
  def self.with_paths(report, paths)
    report.to_h do |name, metrics|
      totals = paths.fetch(name, {}).transform_values do |pair|
        taken, possible = pair
        { 'total' => possible, 'missed' => possible - taken }
      end
      next [name, metrics] if totals.empty?

      [name, metrics.merge('paths' => totals)]
    end
  end

  # True for a {min, max} leaf, even one missing a side.
  def self.bound?(node)
    node.key?('min') || node.key?('max')
  end

  # [] when the value at path in report is within bounds, else
  # its breach line, then a line for each place the report
  # names, in a where list beside it, eg each line missed.
  def self.breach(report, bounds, path)
    value = report.dig(*path)
    problem = bound_problem(bounds) || value_problem(value, bounds)
    return [] unless problem

    where = report.dig(*path[0..-2], 'where') || []
    places = where.map { |place| "  missed: #{place}" }
    ["#{path.join('.')}: #{problem}", *places]
  end

  # Why a bound naming only one side cannot be applied.
  def self.bound_problem(bounds)
    return 'bound names min but no max' unless bounds.key?('max')

    'bound names max but no min' unless bounds.key?('min')
  end

  # Why value fails its bound, or nil when it is within it.
  def self.value_problem(value, bounds)
    return 'missing from the report' if value.nil?

    range = bounds['min']..bounds['max']
    "#{value} is outside #{range}" unless range.cover?(value)
  end
end
