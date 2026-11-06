# path_coverage

- `make all` runs lint, the tests and self-coverage in Docker. It
  must end `coverage: ALLOWED`, with 100% everywhere.
- The file page's panel is a *card*. Never call it a popout.
- After any change to how a card looks, run
  `bin/capture_card_images.sh` to refresh the README's PNGs.
- `bin/build_demo.sh` builds the demo into `site/` (ignored).
- The pages are drawn in the browser by the shared renderer,
  `../html-reporter`, from the data `HtmlData` builds. The files
  in `lib/path_coverage/html/` are its copy: change them there,
  then run `bin/sync_html.sh`.
- Before a refactor of the HTML, CSS or JS, run
  `bin/check_pixels.sh save`; after it, `bin/check_pixels.sh`
  prints same or DIFFERENT for each demo screenshot.
- Test ids come from TidTest; its alphabet has no i I l o O.
  Grep a new id before using it.
- Release: bump version.rb and test/version_test.rb, commit
  "Release X.Y.Z", then build and push as the memory note
  path-coverage-gem-release says.
