#!/usr/bin/env bash
set -Eeu

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly IMAGE=path_coverage-test
readonly REPORTER=ghcr.io/path-coverage/html-reporter
readonly SCHEMAS=ghcr.io/path-coverage/schemas

show_help()
{
  cat <<EOF
Usage: bin/run_tests.sh [OPTIONS] [TID...]

Runs the tests in a Docker image built from the repo's Dockerfile,
with path_coverage measuring its own lib/ and test/ (a renamed
copy of lib/, test/self_coverage.rb, does the measuring), then
checks SimpleCov's report against the bounds in
test/coverage_metrics_params.json, exiting non-zero if a test
fails, a JSON report is invalid against its schema, or a bound is
breached. reports/index.html is SimpleCov's report and
reports/paths/index.html path_coverage's.

With TID arguments, runs only the tests whose tid contains one of
them, and skips the coverage check: a partial run covers only
part of the code, so its report cannot meet the bounds.

The run's seed, printed first, orders both the test files and the
tests. Give SEED to replay a run's order, eg one whose coverage
check failed only once.

Options:
  -h    Show this help

Examples:
  bin/run_tests.sh
  bin/run_tests.sh 2m4 Kp9
  SEED=26820 bin/run_tests.sh
EOF
}

if [ "${1:-}" = '-h' ]; then
  show_help
  exit 0
fi

docker build --quiet --tag "${IMAGE}" "${ROOT_DIR}" > /dev/null

# One seed for the whole run: Minitest reads SEED for the order of
# the tests, and the loader below for the order of the files.
readonly SEED="${SEED:-${RANDOM}}"
echo "seed: ${SEED}"

# A run that dies before SimpleCov writes must not leave the
# previous run's report for the check to pass on. It is deleted
# from inside the container, the side that writes it: deleted on
# the host, the bind mount can then fail to recreate it (ENOENT).
readonly LOADER='
$stdout.sync = true
report = "/reports/coverage_metrics.json"
File.delete(report) if File.exist?(report)
require "/gem/test/self_coverage"
require "/gem/test/simplecov_config"
order = Random.new(Integer(ENV.fetch("SEED")))
Dir["test/**/*_test.rb"].sort.shuffle(random: order).each { |file| require File.expand_path(file) }
SelfCoverage.unhook
'

mkdir -p "${ROOT_DIR}/reports"

# The container runs as the host user who owns reports/, eg a CI
# runner, so it can write there; still not as root.
run_in_image()
{
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "${ROOT_DIR}:/gem:ro" \
    --volume "${ROOT_DIR}/reports:/reports" \
    --env RUBYOPT='-W2 --enable-frozen-string-literal' \
    --env SEED="${SEED}" \
    --env HOST_ROOT="${ROOT_DIR}" \
    "${IMAGE}" \
    "$@"
}

run_in_image ruby -Ilib -Itest -e "${LOADER}" -- "$@"

# The two JSON reports the run wrote into reports/paths, checked
# against their schemas, then path_coverage's own HTML report,
# drawn from them.
docker run --rm \
  --volume "${ROOT_DIR}/reports/paths:/paths:ro" \
  "${SCHEMAS}" /paths > /dev/null
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "${ROOT_DIR}/reports/paths:/paths" \
  "${REPORTER}" /paths

if [ $# -eq 0 ]; then
  run_in_image ruby bin/check_coverage_metrics.rb
fi
