#!/usr/bin/env bash
set -Eeu

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CHROME_IMAGE=ghcr.io/puppeteer/puppeteer:23.10.4
readonly HOME_DIR=/home/pptruser
readonly OUT_DIR="${ROOT_DIR}/reports/pixels"

show_help()
{
  cat <<EOF
Usage: bin/check_pixels.sh [OPTIONS] [save]

Rebuilds the demo into site/, then, in headless Chrome, in the
Puppeteer Docker image, screenshots its index and file pages in
fixed states: on load, a def opened, a loose decision opened, and a
fold opened.
With save, keeps them in reports/pixels/golden/ as the golden.
Without, writes reports/pixels/now/ and prints same or DIFFERENT
for each, so a change that alters what is drawn shows.
Save a golden before a refactor, then check after it.

Options:
  -h    Show this help

Example:
  bin/check_pixels.sh save
  bin/check_pixels.sh
EOF
}

if [ "${1:-}" = '-h' ]; then
  show_help
  exit 0
fi

readonly MODE="${1:-check}"

"${ROOT_DIR}/bin/build_demo.sh" > /dev/null
mkdir -p "${OUT_DIR}"

# Run as root so the bind-mounted reports/pixels/ is writable; the
# module and browser paths then name pptruser's, as root's home
# differs.
docker run --rm \
  --user root \
  --env "MODE=${MODE}" \
  --env "NODE_PATH=${HOME_DIR}/node_modules" \
  --env "PUPPETEER_CACHE_DIR=${HOME_DIR}/.cache/puppeteer" \
  --volume "${ROOT_DIR}/site:/site:ro" \
  --volume "${OUT_DIR}:/out" \
  --volume "${ROOT_DIR}/bin:/capture:ro" \
  "${CHROME_IMAGE}" \
  node /capture/check_pixels.js 2>&1 | grep --invert-match 'WARNING'
