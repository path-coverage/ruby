require_relative 'test_helper'
require 'path_coverage'
require 'open3'

class VersionTest < TidTest
  test 'W3kU10', %w(
  | requiring the gem's entry point defines its version
  ) do
    assert_equal '0.4.0', PathCoverage::VERSION
  end

  test 'W3kU20', %w(
  | requiring the gem's entry point alone loads the kernel,
  | so a consumer needs one require before calling start
  ) do
    # A fresh process: in this one, other tests have
    # already required the kernel directly.
    script = "require 'path_coverage'; " \
             'p PathCoverage.respond_to?(:start)'
    lib = File.expand_path('../lib', __dir__)
    output, status = Open3.capture2e('ruby', '-I', lib, '-e', script)
    assert_equal "true\n", output
    assert status.success?
  end
end
