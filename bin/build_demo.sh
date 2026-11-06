#!/usr/bin/env bash
set -Eeu

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly IMAGE=path_coverage-test
readonly REPORTER=ghcr.io/path-coverage/html-reporter

show_help()
{
  cat <<EOF
Usage: bin/build_demo.sh [OPTIONS]

Runs demo/run.rb, a mock source tree under path coverage, in
the Docker image built from the repo's Dockerfile, writing its
JSON reports to site/, then draws its HTML report there
(index.html first) with the html-reporter image. The same decision
is what the GitHub Pages workflow publishes.

Options:
  -h    Show this help

Example:
  bin/build_demo.sh
EOF
}

if [ "${1:-}" = '-h' ]; then
  show_help
  exit 0
fi

docker build --quiet --tag "${IMAGE}" "${ROOT_DIR}" > /dev/null
mkdir -p "${ROOT_DIR}/site"

# site/ is emptied from inside the container, the side that writes
# it: emptied on the host, the bind mount can then fail to write it.
# The container runs as the host user who owns site/, eg the CI
# runner, so it can write there; still not as root.
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "${ROOT_DIR}:/gem:ro" \
  --volume "${ROOT_DIR}/site:/site" \
  --env COVERAGE_DIR=/site \
  "${IMAGE}" \
  sh -c 'rm -rf /site/* && ruby -Ilib demo/run.rb'

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "${ROOT_DIR}/site:/site" \
  "${REPORTER}" /site

echo "${ROOT_DIR}/site/index.html"
