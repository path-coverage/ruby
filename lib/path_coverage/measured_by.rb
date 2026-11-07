require 'prism'
require_relative 'version'

module PathCoverage
  # The tools that parse and measure a run, each with its version:
  # Ruby, Prism and path_coverage itself. A change to any of them
  # can list a file's decisions or paths differently, so a report
  # names them as it is written, and reports merge only when they
  # name the same.
  module MeasuredBy
    # { tool name => its version } of this process, eg
    # { 'ruby' => '4.0.5', 'prism' => '1.8.1', ... }.
    def self.versions
      {
        'ruby' => RUBY_VERSION, 'prism' => Prism::VERSION,
        'path_coverage' => VERSION
      }
    end
  end
end
