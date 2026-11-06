#!/usr/bin/env bash
# Copies the shared renderer's files into lib/path_coverage/html/.
set -Eeu

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FILES=(page.html pages.json render.js style.css side.js
                settings.js sort.js tabs.js theme.js)

if [ "${1:-}" = '-h' ]; then
  cat <<EOF
Usage: bin/sync_html.sh [REPORTER_DIR]

Copies the shared HTML renderer's files, from REPORTER_DIR (by
default ../html-reporter beside this repo), into
lib/path_coverage/html/, where the gem ships them. The renderer's
repo is their master copy: change them there, then run this.

Options:
  -h    Show this help

Example:
  bin/sync_html.sh ../html-reporter
EOF
  exit 0
fi

readonly FROM="${1:-${ROOT}/../html-reporter}"
for name in "${FILES[@]}"; do
  cp "${FROM}/${name}" "${ROOT}/lib/path_coverage/html/${name}"
done
