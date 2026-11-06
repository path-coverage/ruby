require_relative 'test_helper'
require 'path_coverage/configuration'
require 'path_coverage/json_writer'
require 'path_coverage/manifest'
require 'path_coverage/render'

class RenderTest < TidTest
  test 'Rn5d10', %w(
  | rendering from the JSON reports of several runs
  | reports their merged counts, so only the paths that
  | every run left untaken are listed
  ) do |t|
    source = "def kata?(id) = ok?(id) && id.size == 6\n"
    t.write(source, 'kata.rb')
    sites = PathCoverage::Manifest.sites(source, 'kata.rb')
    site = sites.keys.first
    leaves = [%w(1:16 1:23), %w(1:27 1:39)]
    runs = [
      [[{ truthy: 1, falsy: 0 }, { truthy: 0, falsy: 1 }], [0, 1, 0]],
      [[{ truthy: 0, falsy: 1 }, { truthy: 0, falsy: 0 }], [0, 0, 1]]
    ]
    paths = runs.each_with_index.map do |(operands, counts), n|
      taken = [[true, true], [true, false], [false, nil]]
              .zip(counts).map { |path, count| { path:, count: } }
      file = "#{t.dir}/run#{n}.json"
      report = { site => { leaves:, taken: } }
      writer = PathCoverage::JsonWriter
      writer.write({ site => operands }, file, report)
      file
    end
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report :gaps
    end
    gap = "#{site} path never taken: " \
          '`ok?(id)` true, `id.size == 6` true'
    assert_output("#{gap}\n", '') do
      PathCoverage::Render.from_json(config, paths)
    end
  end

  test 'Rn5d11', %w(
  | Example: kata?'s && in two runs, one taking its middle
  | path, the other its last
  | Rendering from their JSON reports writes the merged JSON
  | report into coverage_dir, each path's count the sum of
  | both runs', and the source report beside it, as a run
  | does, for html-reporter to draw.
  ) do |t|
    source = "def kata?(id) = ok?(id) && id.size == 6\n"
    t.write(source, 'kata.rb')
    site = PathCoverage::Manifest.sites(source, 'kata.rb').keys.first
    leaves = [%w(1:16 1:23), %w(1:27 1:39)]
    operands = [{ truthy: 1, falsy: 1 }, { truthy: 0, falsy: 1 }]
    runs = [[0, 1, 0], [0, 0, 1]].each_with_index.map do |counts, n|
      taken = [[true, true], [true, false], [false, nil]]
              .zip(counts).map { |path, count| { path:, count: } }
      file = "#{t.dir}/run#{n}.json"
      report = { site => { leaves:, taken: } }
      writer = PathCoverage::JsonWriter
      writer.write({ site => operands }, file, report)
      file
    end
    out = "#{t.dir}/merged"
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir out
      report
    end
    PathCoverage::Render.from_json(config, runs)

    merged = JSON.parse(File.read("#{out}/path_coverage.json"))
    counts = merged['paths'][site]['taken'].map { _1['count'] }
    assert_equal [0, 1, 1], counts
    written = File.read("#{out}/path_coverage.source.json")
    kata = JSON.parse(written)['files']['kata.rb']
    assert_equal [site], kata['sites'].keys
  end

  test 'Rn5d20', %w(
  | a JSON report with no paths, eg from an older version,
  | cannot say which paths were taken, so rendering from it
  | reports every path of each site it reached as never
  | taken, rather than claiming any was
  ) do |t|
    source = "def kata?(id) = ok?(id) && id.size == 6\n"
    t.write(source, 'kata.rb')
    sites = PathCoverage::Manifest.sites(source, 'kata.rb')
    site = sites.keys.first
    operands = [{ truthy: 1, falsy: 1 }, { truthy: 1, falsy: 0 }]
    file = "#{t.dir}/run.json"
    PathCoverage::JsonWriter.write({ site => operands }, file)
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report :gaps
    end
    never = "#{site} path never taken: `ok?(id)`"
    expected = [
      "#{never} true, `id.size == 6` true",
      "#{never} true, `id.size == 6` false",
      "#{never} false"
    ].join("\n")
    assert_output("#{expected}\n", '') do
      PathCoverage::Render.from_json(config, [file])
    end
  end

  test 'Rn5d30', %w(
  | a JSON report from a run that measured other kinds, eg
  | one with writes switched off, lists its sites' paths
  | differently, so rendering from it is refused rather than
  | crediting one path's count to another
  ) do |t|
    source = "def kata?(id) = ok?(id) && id.size == 6\n"
    t.write(source, 'kata.rb')
    sites = PathCoverage::Manifest.sites(source, 'kata.rb')
    site = sites.keys.first
    operands = [{ truthy: 1, falsy: 1 }, { truthy: 1, falsy: 0 }]
    file = "#{t.dir}/run.json"
    PathCoverage::JsonWriter.write({ site => operands }, file)
    json = JSON.parse(File.read(file))
    json['kinds'] -= ['write']
    File.write(file, JSON.generate(json))
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report :gaps
    end
    error = assert_raises(ArgumentError) do
      PathCoverage::Render.from_json(config, [file])
    end
    assert_equal "#{file} measured other kinds", error.message
  end

  test 'Rn5d31', %w(
  | Example: a JSON report from a run with ignore '&&', rendered
  | with nothing ignored
  | The render would list the && site's paths, which the run
  | never measured, so rendering from it is refused.
  ) do |t|
    source = "def kata?(id) = ok?(id) && id.size == 6\n"
    t.write(source, 'kata.rb')
    file = "#{t.dir}/run.json"
    fingerprint = { 'ignored' => ['&&'] }
    PathCoverage::JsonWriter.write({}, file, fingerprint:)
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report :gaps
    end
    error = assert_raises(ArgumentError) do
      PathCoverage::Render.from_json(config, [file])
    end
    assert_equal "#{file} measured other kinds", error.message
  end

  test 'Rn5d32', %w(
  | Example: report :summary with ignore '&&=', '||='
  | The summary names the operators ignored after its totals,
  | so a total that leaves out their sites never passes for
  | one that measured them.
  ) do |t|
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report :summary
      ignore '&&=', '||='
    end
    expected = [
      'Paths alone: 0 / 0 (-)',
      'Paths combined: 0 / 0 (-)',
      'Path coverage ignores: &&=, ||='
    ].join("\n")
    assert_output("#{expected}\n", '') do
      PathCoverage::Render.run({}, {}, config)
    end
  end

  test 'Rn5d33', %w(
  | Example: a JSON report from a run with treat 'name', as:
  | :present, rendered with no treat
  | The run listed no nil path for a name&. receiver, the render
  | would, so rendering from it is refused.
  ) do |t|
    t.write("def size(u) = u.name&.size\n", 'size.rb')
    file = "#{t.dir}/run.json"
    fingerprint = { 'treats' => [['name', 'present', nil]] }
    PathCoverage::JsonWriter.write({}, file, fingerprint:)
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report :gaps
    end
    error = assert_raises(ArgumentError) do
      PathCoverage::Render.from_json(config, [file])
    end
    assert_equal "#{file} measured other kinds", error.message
  end

  test 'Rn5d34', %w(
  | Example: two JSON reports of runs measuring methods, one
  | reaching a write twice, the other the write once and a
  | value once
  | Their reaches are read back, each statement's the sum of
  | both runs'.
  ) do |t|
    runs = [{ 'k.rb:2:2' => 2 }, { 'k.rb:2:2' => 1, 'k.rb:3:2' => 1 }]
    files = runs.map.with_index do |reached, i|
      file = "#{t.dir}/#{i}.json"
      PathCoverage::JsonWriter.write({}, file, reached:)
      file
    end
    taken = PathCoverage::JsonReader.taken(files)
    expected = { 'k.rb:2:2' => 3, 'k.rb:3:2' => 1 }
    assert_equal expected, taken[:reached]
  end

  test 'Rn5d35', %w(
  | Example: a JSON report with no reaches, as the :post
  | reporter sends
  | None are read back, so a render cannot say whether a
  | statement was reached.
  ) do |t|
    file = "#{t.dir}/run.json"
    PathCoverage::JsonWriter.write({}, file)
    assert_nil PathCoverage::JsonReader.taken([file])[:reached]
  end

  test 'Rn5d36', %w(
  | Example: a local run's JSON report reaching a write twice,
  | and a posted one with no reaches
  | The reaches read back are the local run's alone, as the
  | posted run says nothing of what it reached.
  ) do |t|
    local = "#{t.dir}/local.json"
    reached = { 'k.rb:2:2' => 2 }
    PathCoverage::JsonWriter.write({}, local, reached:)
    posted = "#{t.dir}/posted.json"
    PathCoverage::JsonWriter.write({}, posted)
    taken = PathCoverage::JsonReader.taken([local, posted])
    assert_equal({ 'k.rb:2:2' => 2 }, taken[:reached])
  end
end
