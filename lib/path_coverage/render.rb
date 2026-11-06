require_relative 'console_summary'
require_relative 'gaps'
require_relative 'json_reader'
require_relative 'json_reports'
require_relative 'manifest'
require_relative 'paths_report'
require_relative 'post'
require_relative 'decision_paths'
require_relative 'within_methods'

module PathCoverage
  # The JSON reports and the reporters, run from operands alone:
  # needing nothing the run recorded beyond them, they can run in
  # another process.
  module Render
    # Writes the JSON reports, then runs each reporter chosen in
    # config. operands, and taken's decision_paths: and outside:, are
    # as Result gives them, and its reached: as Recorder#reached
    # gives it; files is { full path => {source:, decisions:} } for
    # each covered file.
    def self.run(operands, files, config, **taken)
      recorded = taken.merge(
        decision_paths: every_decision(
          taken.fetch(:decision_paths, {}), files
        ),
        outside: taken.fetch(:outside, {})
      )
      JsonReports.write(operands, files, config, **recorded)
      reporters(operands, files, config, recorded)
    end

    # Runs each reporter chosen in config, from operands, files,
    # and recorded, as run has them.
    def self.reporters(operands, files, config, recorded)
      decision_paths = recorded[:decision_paths]
      chosen = config.reporters
      if chosen.include?(:gaps)
        gaps(operands, files, decision_paths, recorded[:outside])
      end
      if chosen.include?(:summary)
        summary(files, config, decision_paths, recorded[:reached])
      end
      return unless chosen.include?(:post)

      post(operands, files, config, decision_paths)
    end

    # Runs the :post reporter: operands, and the paths report of
    # decision_paths in files, with config's fingerprint.
    def self.post(operands, files, config, decision_paths)
      report = PathsReport.of(decision_paths, files)
      url = config.collector_url
      fingerprint = config.fingerprint
      Post.deliver(operands, url, report, fingerprint:)
    end

    # Prints the summary lines: the paths taken of all possible
    # alone, and combined, each def's card of files as decision_paths
    # and reached have it; then any operators ignored.
    def self.summary(files, config, decision_paths, reached)
      cards = WithinMethods.cards(files, config, decision_paths,
                                  reached)
      puts ConsoleSummary.lines(decision_paths, cards,
                                config.groups) +
           ConsoleSummary.ignored_lines(config.ignored)
    end

    # decision_paths with every decision in files that it lacks, eg
    # from a JSON report with no paths, given each possible
    # path at a count of zero: unable to say which paths such
    # a decision took, the report claims none.
    def self.every_decision(decision_paths, files)
      none = files.values.each_with_object({}) do |parsed, all|
        parsed[:decisions].each do |decision, condition|
          possible = DecisionPaths.possible(condition)
          all[decision] = possible.map { |path| { path:, count: 0 } }
        end
      end
      none.merge(decision_paths)
    end

    # Prints the gap lines: each path a decision never took, and each
    # path taken that a treatment rules out, as outside lists
    # them, each leaf named by its text in files.
    def self.gaps(operands, files, decision_paths, outside)
      texts = PathsReport.texts(files)
      paths = decision_paths
      lines = Gaps.lines(operands, paths:, texts:, outside:)
      lines.each { |line| puts line }
    end

    # Runs the reporters chosen in config from the JSON reports
    # at paths, their counts and reaches merged, parsing each
    # covered file afresh. paths is config.json_path alone by
    # default.
    def self.from_json(config, paths = [config.json_path])
      operands = JsonReader.operands(paths, config.fingerprint)
      files = config.files.to_h do |path|
        [path, Manifest.parse(path, config)]
      end
      run(operands, files, config, **JsonReader.taken(paths))
    end
  end
end
