require_relative 'console_summary'
require_relative 'gaps'
require_relative 'json_reader'
require_relative 'manifest'
require_relative 'paths_report'
require_relative 'post'
require_relative 'site_paths'
require_relative 'within_methods'

module PathCoverage
  # The reporters, run from operands alone: needing nothing the
  # run recorded beyond them, they can run in another process.
  module Render
    # Runs each reporter chosen in config. operands, and taken's
    # site_paths: and outside:, are as Result gives them, and its
    # reached: as Recorder#reached gives it; files is
    # { full path => {source:, sites:} } for each covered file.
    def self.run(operands, files, config, **taken)
      site_paths = every_site(taken.fetch(:site_paths, {}), files)
      reporters = config.reporters
      if reporters.include?(:gaps)
        gaps(operands, files, site_paths, taken.fetch(:outside, {}))
      end
      if reporters.include?(:summary)
        summary(files, config, site_paths, taken[:reached])
      end
      return unless reporters.include?(:post)

      post(operands, files, config, site_paths)
    end

    # Runs the :post reporter: operands, and the paths report of
    # site_paths in files, with config's fingerprint.
    def self.post(operands, files, config, site_paths)
      report = PathsReport.of(site_paths, files)
      url = config.collector_url
      fingerprint = config.fingerprint
      Post.deliver(operands, url, report, fingerprint:)
    end

    # Prints the summary lines: the paths taken of all possible
    # within decisions, and within methods, each def's card of
    # files as site_paths and reached have it; then any operators
    # ignored.
    def self.summary(files, config, site_paths, reached)
      cards = WithinMethods.cards(files, config, site_paths, reached)
      puts ConsoleSummary.lines(site_paths, cards, config.groups) +
           ConsoleSummary.ignored_lines(config.ignored)
    end

    # site_paths with every site in files that it lacks, eg
    # from a JSON report with no paths, given each possible
    # path at a count of zero: unable to say which paths such
    # a site took, the report claims none.
    def self.every_site(site_paths, files)
      none = files.values.each_with_object({}) do |parsed, all|
        parsed[:sites].each do |site, condition|
          all[site] = SitePaths.possible(condition).map do |path|
            { path:, count: 0 }
          end
        end
      end
      none.merge(site_paths)
    end

    # Prints the gap lines: each path a site never took, and each
    # path taken that a treatment rules out, as outside lists
    # them, each leaf named by its text in files.
    def self.gaps(operands, files, site_paths, outside)
      texts = PathsReport.texts(files)
      paths = site_paths
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
