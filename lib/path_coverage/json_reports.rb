require 'fileutils'
require 'json'
require_relative 'paths_gaps'
require_relative 'console_summary'
require_relative 'json_writer'
require_relative 'paths_report'
require_relative 'source_report'
require_relative 'within_methods'

module PathCoverage
  # The two JSON reports every run writes, and every render of
  # runs merged, into coverage_dir: path_coverage.json, the
  # counts, and path_coverage.source.json, what drawing each
  # file's code needs, for html-reporter to draw the pages from.
  module JsonReports
    # What WithinMethods reads of a run: operands, decision paths,
    # and paths a treatment rules out, as Result gives them.
    Recorded = Data.define(:operands, :paths, :outside)

    # Writes both reports into config's coverage_dir, created
    # first if need be. operands, and taken's decision_paths: and
    # outside:, are as Result gives them, taken's reached: as
    # Recorder#reached gives it, nil when not known; files is
    # { full path => {source:, decisions:} } for each covered file.
    def self.write(operands, files, config, **taken)
      FileUtils.mkdir_p(config.output_dir)
      paths = taken.values_at(:decision_paths, :outside)
      recorded = Recorded.new(operands, *paths)
      reached = taken[:reached]
      flows = WithinMethods.listed(files, config, recorded,
                                   [reached, taken[:ways]])
      tree = WithinMethods.tree(files, config, recorded)
      write_json(recorded, files, config, [flows, reached, tree])
      write_ways(flows, files, config, tree)
      write_source(files, config, recorded.paths, flows)
    end

    # Writes recorded as the JSON report at config's json_path:
    # its operands, decision paths, paths a treatment rules out,
    # totals, flows, each def's flow, as WithinMethods.listed
    # gives them, tree, how each flow's rows nest, the statements
    # reached, when known, and config's fingerprint and limits.
    def self.write_json(recorded, files, config, listed)
      flows, reached, tree = listed
      report = PathsReport.of(recorded.paths, files)
      totals = totals(recorded.paths, files, config, reached)
      limits = { 'loops' => config.loops?,
                 'max_paths' => config.path_limit }
      parts = { totals:, outside: recorded.outside, flows:, tree:,
                fingerprint: config.fingerprint, limits: }
      parts[:reached] = reached if reached
      path = config.json_path
      JsonWriter.write(recorded.operands, path, report, **parts)
    end

    # Writes the ways lines, each method's untested paths, as
    # PathsGaps.lines gives them for flows, beside the JSON report,
    # at ways_path, so a later check, or the :ways reporter, can
    # show them; tree is how each flow's rows nest, as
    # WithinMethods.tree gives it.
    def self.write_ways(flows, files, config, tree)
      texts = PathsReport.texts(files)
      lines = PathsGaps.lines(flows, texts, parents_of(tree))
      File.write(ways_path(config), lines.map { "#{_1}\n" }.join)
    end

    # { row's decision => its parent's decision } of each row in
    # tree that runs inside another row, as WithinMethods.tree
    # gives it. Each decision is named path:line:column.
    def self.parents_of(tree)
      tree.flat_map do |path, nested|
        nested.values.flat_map do |rows|
          rows.filter_map do |at, place|
            next unless place['parent']

            ["#{path}:#{at}", "#{path}:#{place['parent']}"]
          end
        end
      end.to_h
    end

    # Where the ways lines go, beside the JSON report.
    def self.ways_path(config)
      config.json_path.sub(/\.json\z/, '.ways.txt')
    end

    # Writes the source report beside the JSON report, from
    # files, decision_paths and flows, as write has them.
    def self.write_source(files, config, decision_paths, flows)
      source = SourceReport.of(files, config, decision_paths, flows)
      path = config.json_path.sub(/\.json\z/, '.source.json')
      File.write(path, JSON.generate(source))
    end

    # The JSON report's totals, each [taken, possible] paths:
    # within each decision, and within each method; with groups
    # configured, each group's own too, under groups.
    def self.totals(decision_paths, files, config, reached)
      flows = WithinMethods.flows(files, config, decision_paths,
                                  reached)
      totals = ConsoleSummary.totals(decision_paths, flows)
      groups = config.groups
      return totals if groups.empty?

      own = ConsoleSummary.group_totals(decision_paths, flows, groups)
      totals.merge('groups' => own)
    end
  end
end
