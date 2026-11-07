.PHONY: all image test test_core test_check lint demo

# Everything a change must pass before it is committed.
all: lint test test_check

image:
	docker build --tag path_coverage-test ${PWD}

# Runs the tests with path_coverage measuring its own lib/ and
# test/. A full run also gates SimpleCov's report against
# test/coverage_metrics_params.json. tids runs only the tests
# whose tid contains one of its values, and skips that gate.
#   eg make test tids='6D1K p0Kj'
test:
	${PWD}/bin/run_tests.sh ${tids}

# Runs every test but the generated ones in test/property, and
# gates the result: whether the hand-written tests alone reach
# the bounds.
test_core:
	${PWD}/bin/run_tests.sh --suite core

# Check that the coverage gate can fail: that a breached bound
# reaches make as a non-zero exit, not merely a line of output.
test_check:
	bash ${PWD}/test/sh/test_check_coverage_metrics.sh

lint:
	${PWD}/bin/lint.sh

# Build the demo report into site/, the same site GitHub Pages
# publishes, and open it in a browser where one can be found.
demo:
	${PWD}/bin/build_demo.sh
	@if command -v open > /dev/null; then open ${PWD}/site/index.html; \
	elif command -v xdg-open > /dev/null; then xdg-open ${PWD}/site/index.html; fi
