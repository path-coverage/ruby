# The suites a run can be, each the test files it loads and
# whether its coverage is checked: all, every test; core, the
# hand-written tests, without the generated ones in
# test/property; property, those alone. The one place a suite is
# decided, read by the loader in bin/run_tests.sh, by
# self_coverage.rb, by simplecov_config.rb and by
# bin/check_coverage_metrics.rb. PATH_COVERAGE_SUITE names the
# suite, all when unset.
module Suites
  EVERY = 'test/**/*_test.rb'.freeze
  PROPERTY = 'test/property/**/*.rb'.freeze

  # A property-only run covers only part of the code, so, as a run
  # of chosen tids, its coverage is not checked.
  TABLE = {
    'all' => { with: EVERY, without: [], checked: true },
    'core' => { with: EVERY, without: [PROPERTY], checked: true },
    'property' => {
      with: 'test/property/**/*_test.rb', without: [], checked: false
    }
  }.freeze

  # The current suite's name, from PATH_COVERAGE_SUITE; raises
  # KeyError for a name TABLE does not have.
  def self.name
    named = ENV.fetch('PATH_COVERAGE_SUITE', 'all')
    TABLE.fetch(named) { raise KeyError, "no suite named #{named}" }
    named
  end

  # The test files, relative to the root, the current suite loads,
  # in name order.
  def self.files
    Dir[TABLE[name][:with]].reject { |path| excluded?(path) }.sort
  end

  # The globs, relative to the root, of the files the current suite
  # leaves out, so neither runs nor measures.
  def self.excluded
    TABLE[name][:without]
  end

  # True for path, relative to the root, when the current suite
  # leaves it out.
  def self.excluded?(path)
    excluded.any? do |glob|
      File.fnmatch?(glob, path, File::FNM_PATHNAME)
    end
  end

  # True when the current suite's coverage is checked against the
  # bounds in test/coverage_metrics_params.json.
  def self.checked?
    TABLE[name][:checked]
  end
end
