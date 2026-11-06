require_relative 'test_helper'
require 'path_coverage/configuration'

class ConfigurationTest < TidTest
  test 'A9MJ10', %w(
  | a misspelt setting in the start block is refused,
  | naming it and listing the settings there are,
  | rather than failing with a NoMethodError
  ) do
    error = assert_raises(PathCoverage::ConfigurationError) do
      PathCoverage::Configuration.new do
        root '/app'
        covr 'source/**/*.rb'
      end
    end
    expected = [
      'unknown setting covr in PathCoverage.start',
      'the settings are: ' \
      'collector, cover, coverage_dir, group, ignore, ' \
      'report, root, skip, treat'
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'A9MJ50', %w(
  | Example: group 'Models', 'source/models/**/*.rb'
  | and group 'Routes', 'source/app/routes_*.rb', 'source/api/*.rb'
  | groups names each group's globs, in the order given.
  | With no group setting there are none.
  ) do
    config = PathCoverage::Configuration.new do
      root '/app'
      group 'Models', 'source/models/**/*.rb'
      group 'Routes', 'source/app/routes_*.rb', 'source/api/*.rb'
    end
    expected = {
      'Models' => ['source/models/**/*.rb'],
      'Routes' => ['source/app/routes_*.rb', 'source/api/*.rb']
    }
    assert_equal expected, config.groups
    plain = PathCoverage::Configuration.new { root '/app' }
    assert_equal({}, plain.groups)
  end

  test 'A9MJ40', %w(
  | Example: cover 'source/**/*.rb', skip 'source/vendor/**/*.rb'
  | A file a skip glob matches is not covered, though a cover
  | glob matches it too.
  | So it is neither among the files reported nor instrumented.
  | Every other covered file still is.
  ) do |t|
    t.write("ok = 1\n", 'source/kata.rb')
    t.write("ok = 2\n", 'source/vendor/zip.rb')
    config = PathCoverage::Configuration.new do
      root t.dir
      cover 'source/**/*.rb'
      skip 'source/vendor/**/*.rb'
    end
    assert_equal ["#{t.dir}/source/kata.rb"], config.files
    covered = %w(kata.rb vendor/zip.rb).map do |name|
      config.covers?("#{t.dir}/source/#{name}")
    end
    assert_equal [true, false], covered
  end

  test 'A9MJ60', %w(
  | Example: cover 'source/**/*.rb', skip 'source/**'
  | With no files under source, there are no files.
  | With kata.rb, it is skipped, so there are none.
  | With kata.rb and team.rb, both are skipped, so there are none.
  ) do |t|
    runs = [[], %w(kata.rb), %w(kata.rb team.rb)]
    actual = runs.map.with_index do |names, n|
      dir = "#{t.dir}/#{n}"
      FileUtils.mkdir_p("#{dir}/source")
      names.each do |name|
        File.write("#{dir}/source/#{name}", "ok = 1\n")
      end
      config = PathCoverage::Configuration.new do
        root dir
        cover 'source/**/*.rb'
        skip 'source/**'
      end
      config.files
    end
    assert_equal [[], [], []], actual
  end

  test 'A9MJ70', %w(
  | Example: no cover, cover 'source/*.rb', and cover 'lib/*.rb'
  | with cover 'source/*.rb'
  | With no cover glob, no file is covered.
  | source/kata.rb is covered when any glob matches it.
  | test/kata_test.rb is covered by none of them.
  ) do
    covers = [[], %w(source/*.rb), %w(lib/*.rb source/*.rb)]
    configs = covers.map do |globs|
      PathCoverage::Configuration.new do
        root '/app'
        globs.each { |glob| cover glob }
      end
    end
    actual = configs.map do |config|
      %w(source/kata.rb test/kata_test.rb).map do |path|
        config.covers?("/app/#{path}")
      end
    end
    expected = [[false, false], [true, false], [true, false]]
    assert_equal expected, actual
  end

  test 'A9MJ15', %w(
  | an unknown reporter in the start block is refused, eg
  | :html, whose report html-reporter draws from the JSON,
  | naming it and listing the reporters there are
  ) do
    error = assert_raises(PathCoverage::ConfigurationError) do
      PathCoverage::Configuration.new do
        root '/app'
        report :gaps, :html
      end
    end
    expected = [
      'unknown reporter html in PathCoverage.start',
      'the reporters are: gaps, post, summary'
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'A9MJ20', %w(
  | a configuration does not claim to respond to a setting
  | that does not exist
  ) do
    config = PathCoverage::Configuration.new { root '/app' }
    refute config.respond_to?(:covr)
  end

  test 'A9MJ30', %w(
  | Example: measure :decisions, :methods in the start block
  | Paths are one measure, so there is nothing to choose: it
  | is refused as an unknown setting, listing those there are.
  ) do
    error = assert_raises(PathCoverage::ConfigurationError) do
      PathCoverage::Configuration.new do
        root '/app'
        measure :decisions, :methods
      end
    end
    expected = [
      'unknown setting measure in PathCoverage.start',
      'the settings are: ' \
      'collector, cover, coverage_dir, group, ignore, ' \
      'report, root, skip, treat'
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'A9MJ80', %w(
  | Example: ignore '&&=', '||='
  | ignored names each operator whose sites are not measured.
  | With no ignore setting none are.
  ) do
    config = PathCoverage::Configuration.new do
      root '/app'
      ignore '&&=', '||='
    end
    assert_equal ['&&=', '||='], config.ignored
    plain = PathCoverage::Configuration.new { root '/app' }
    assert_equal [], plain.ignored
  end

  test 'A9MJ81', %w(
  | an unknown operator to ignore is refused, naming it and
  | listing the operators there are, as ignoring nothing would
  | leave its sites measured unnoticed
  ) do
    error = assert_raises(PathCoverage::ConfigurationError) do
      PathCoverage::Configuration.new do
        root '/app'
        ignore '=&&'
      end
    end
    known = PathCoverage::Kinds::BY_OPERATOR.keys.join(', ')
    expected = [
      'unknown operator =&& in PathCoverage.start',
      "the operators are: #{known}"
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'A9MJ82', %w(
  | Example: treat 'name', as: :present, in: 'source/models/**'
  | treated names each method treated as never nil in a
  | covered file its glob matches, and none in any other.
  | With no in: every covered file matches.
  ) do
    config = PathCoverage::Configuration.new do
      root '/app'
      treat 'name', as: :present, in: 'source/models/**'
      treat 'owner', as: :present
    end
    models = config.treated('present', 'source/models/user.rb')
    others = config.treated('present', 'source/app/routes.rb')
    assert_equal [%w(name owner), %w(owner)], [models, others]
  end

  test 'A9MJ84', %w(
  | Example: treat 'any?', as: :nonempty, and treat 'name', as:
  | :present
  | Each treatment names only the methods treated as it.
  ) do
    config = PathCoverage::Configuration.new do
      root '/app'
      treat 'any?', as: :nonempty
      treat 'name', as: :present
    end
    path = 'source/kata.rb'
    actual = %w(nonempty present).map { config.treated(_1, path) }
    assert_equal [%w(any?), %w(name)], actual
  end

  test 'A9MJ83', %w(
  | a method treated as something other than present is
  | refused, naming it and listing what a method can be
  | treated as
  ) do
    error = assert_raises(PathCoverage::ConfigurationError) do
      PathCoverage::Configuration.new do
        root '/app'
        treat 'name', as: :presnet
      end
    end
    expected = [
      'unknown treatment presnet in PathCoverage.start',
      'the treatments are: present, nonempty'
    ].join("\n")
    assert_equal expected, error.message
  end
end
