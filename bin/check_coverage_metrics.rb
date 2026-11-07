#!/usr/bin/env ruby
require 'json'
require_relative '../test/coverage_metrics_check'
require_relative '../test/suites'

HELP = <<~TEXT.freeze
  Usage: bin/check_coverage_metrics.rb [OPTIONS] [REPORT] [PARAMS] [PATHS]

  Prints each group's line, branch and path coverage, then checks
  a coverage report against the min..max bounds in a params file,
  printing each breached bound, and exits non-zero if any bound
  is breached. A suite of test/suites.rb whose coverage is not
  checked, named by PATH_COVERAGE_SUITE, is not checked here
  either.

  REPORT defaults to reports/coverage_metrics.json, which
  bin/run_tests.sh writes; PARAMS to
  test/coverage_metrics_params.json; PATHS, path_coverage's
  report, to reports/paths/path_coverage.json when REPORT is not
  given, and is skipped when absent.

  Options:
    -h    Show this help

  Example:
    bin/check_coverage_metrics.rb
TEXT

ROOT = File.expand_path('..', __dir__)

# The parsed JSON at path, or exits naming what is wrong with it.
def read_json(path)
  JSON.parse(File.read(path))
rescue Errno::ENOENT
  abort("#{path}: no such file")
rescue JSON::ParserError => e
  abort("#{path}: not valid JSON: #{e.message}")
end

if ARGV.first == '-h'
  puts HELP
  exit 0
end

unless Suites.checked?
  puts "coverage: not checked (suite #{Suites.name})"
  exit 0
end

report = ARGV[0] || "#{ROOT}/reports/coverage_metrics.json"
params = ARGV[1] || "#{ROOT}/test/coverage_metrics_params.json"
bounds = read_json(params).fetch('bounds') do
  abort("#{params}: no \"bounds\" key, so nothing would be checked")
end
metrics = read_json(report)
# path_coverage's own per-group totals, when its report is there,
# so each group shows all four of its figures together. Given a
# REPORT, only a PATHS given too is read.
default_paths = "#{ROOT}/reports/paths/path_coverage.json"
path_report = ARGV[2] || (ARGV[0] ? nil : default_paths)
paths = {}
if path_report && File.exist?(path_report)
  paths = read_json(path_report).dig('totals', 'groups') || {}
end
puts CoverageMetricsCheck.groups(metrics, paths)
# The path totals join the metrics, so bounds gate them too, eg
# test.paths.combined.missed; a bound on a path total with no path
# report is a breach, missing from the report.
merged = CoverageMetricsCheck.with_paths(metrics, paths)
breaches = CoverageMetricsCheck.breaches(merged, bounds)
breaches.each { |line| puts line }
# Where to look, each report with a code and a test tab, just
# before the verdict on them; only when run for a host, whose
# paths HOST_ROOT names.
host = ENV.fetch('HOST_ROOT', '')
unless host.empty?
  puts "SimpleCov report: #{host}/reports/index.html"
  puts "PathCov report: #{host}/reports/paths/index.html"
end
puts breaches.empty? ? 'coverage: ALLOWED' : 'coverage: DENIED'
exit breaches.empty?
