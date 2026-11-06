#!/usr/bin/env bash
set -Eeu

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUBY_IMAGE=path_coverage-test
readonly CHROME_IMAGE=ghcr.io/puppeteer/puppeteer:23.10.4
readonly REPORTER=ghcr.io/path-coverage/html-reporter
readonly HOME_DIR=/home/pptruser
readonly REPORT_DIR="${ROOT_DIR}/reports/cards"

show_help()
{
  cat <<EOF
Usage: bin/capture_card_images.sh [OPTIONS]

Runs demo/cards/run.rb, one method per kind of card cell,
under path coverage, writing its JSON reports to reports/cards/,
and draws its HTML report there with the html-reporter image.
Then, in headless Chrome, in the Puppeteer Docker image, saves
each method's card to docs/, eg docs/cell-blank.png, and each
example page, its card open, eg docs/example-taken.png, for the
README's Reading the HTML.
Run it again whenever the card's look changes.

Options:
  -h    Show this help

Example:
  bin/capture_card_images.sh
EOF
}

if [ "${1:-}" = '-h' ]; then
  show_help
  exit 0
fi

docker build --quiet --tag "${RUBY_IMAGE}" "${ROOT_DIR}" > /dev/null
mkdir -p "${REPORT_DIR}" "${ROOT_DIR}/docs"

# The report dir is emptied from inside the container, the side
# that writes it.
docker run --rm \
  --volume "${ROOT_DIR}:/gem:ro" \
  --volume "${REPORT_DIR}:/report" \
  --env COVERAGE_DIR=/report \
  "${RUBY_IMAGE}" \
  sh -c 'rm -rf /report/* && ruby -Ilib demo/cards/run.rb'

docker run --rm \
  --volume "${REPORT_DIR}:/report" \
  "${REPORTER}" /report

# Run as root so the bind-mounted docs/ is writable; the module
# and browser paths then name pptruser's, as root's home differs.
docker run --rm \
  --user root \
  --env "NODE_PATH=${HOME_DIR}/node_modules" \
  --env "PUPPETEER_CACHE_DIR=${HOME_DIR}/.cache/puppeteer" \
  --volume "${REPORT_DIR}:/report:ro" \
  --volume "${ROOT_DIR}/docs:/out" \
  --volume "${ROOT_DIR}/bin:/capture:ro" \
  "${CHROME_IMAGE}" \
  node /capture/capture_card_images.js

ls "${ROOT_DIR}"/docs/cell-*.png "${ROOT_DIR}"/docs/example-*.png
