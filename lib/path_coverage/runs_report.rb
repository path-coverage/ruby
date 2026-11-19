require 'json'
require_relative 'configuration'
require_relative 'render'
require_relative 'ways_totals'

module PathCoverage
  # The path_coverage_report command: reports saved runs' JSON
  # reports as one, each loop a decision only when asked.
  module RunsReport
    HELP = <<~HELP.freeze
      Usage: path_coverage_report [--loops] [--max-paths N] SOURCE_ROOT GLOBS REPORT_DIR RUN_JSON...

      Reports the saved runs RUN_JSON... as one, writing the report into
      REPORT_DIR, then prints each method's untested paths and the totals.
      Exits 0 when every path is taken, and 1 when any is not.

        SOURCE_ROOT  the directory holding the covered source
        GLOBS        comma-separated globs of the covered files, relative to SOURCE_ROOT
        REPORT_DIR   the directory it writes its report into
        RUN_JSON...  one or more saved runs' JSON files, space-separated

      Options:
        -h             Show this help
        --loops        Count each loop as a decision: 0 items or 1+ items
        --max-paths N  Fail each method with more than N paths
                       (default 4096, at most 65536)

      Example:
        path_coverage_report --max-paths 8 /app 'lib/**/*.rb' report runs/*.json
    HELP

    # Reports the runs argv names, [--loops] [--max-paths N]
    # SOURCE_ROOT GLOBS REPORT_DIR RUN_JSON..., as HELP says,
    # printing the untested paths, then the totals, read from the
    # JSON it wrote, so a run with no untested path still prints
    # them; -h prints HELP. Returns the exit status: 1 when the
    # report fails, as WaysTotals.failed? says, else 0.
    def self.main(argv)
      return help if argv.first == '-h'

      options, (source_root, globs, report_dir, *runs) = options(argv)
      config = configured(source_root, globs, report_dir, options)
      Render.from_json(config, runs)
      written = JSON.parse(File.read(config.json_path))
      puts WaysTotals.lines(written)
      WaysTotals.failed?(written) ? 1 : 0
    end

    # Prints HELP; returns 0.
    def self.help
      print HELP
      0
    end

    # [{ loops:, max_paths: }, the rest of argv] of argv's leading
    # options; loops false and max_paths the default when not
    # given.
    def self.options(argv)
      options = { loops: false, max_paths: Configuration::MAX_PATHS }
      rest = argv.dup
      while %w[--loops --max-paths].include?(rest.first)
        flag = rest.shift
        next options[:loops] = true if flag == '--loops'

        options[:max_paths] = Integer(rest.shift)
      end
      [options, rest]
    end

    # The configuration reporting the files globs, comma-separated,
    # match under source_root into report_dir, with the :ways
    # reporter and options' loops and max_paths.
    def self.configured(source_root, globs, report_dir, options)
      Configuration.new do
        root source_root
        globs.split(',').each { cover _1 }
        coverage_dir report_dir
        report :ways
        max_paths options[:max_paths]
        loops if options[:loops]
      end
    end
  end
end
