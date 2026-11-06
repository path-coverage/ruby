require_relative 'test_helper'
require 'path_coverage/json_writer'
require 'path_coverage/result'
require 'json'

class JsonWriterTest < TidTest
  test 'wdt910', %w(
  | the result is written as raw JSON under "decisions",
  | the base every other reporter reads, with the names of
  | the kinds of decision measured under "kinds", so runs that
  | measured different kinds are never merged
  ) do |t|
    decisions = { 'k.rb:2:2' => condition('&&', 16...23, 27...35) }
    counts = { ['k.rb:2:2', 0] => { truthy: 1, falsy: 1 } }
    operands = PathCoverage::Result.new(decisions, counts).operands
    path = "#{t.dir}/path_coverage.json"
    PathCoverage::JsonWriter.write(operands, path)
    expected = {
      'decisions' => {
        'k.rb:2:2' => [
          { 'truthy' => 1, 'falsy' => 1 },
          { 'truthy' => 0, 'falsy' => 0 }
        ]
      },
      'kinds' => %w(block case chain choice contains safe write)
    }
    actual = JSON.parse(File.read(path))
    assert_equal expected, actual
  end

  test 'wdt911', %w(
  | Example: a run with ignore '&&='
  | The operators ignored are written under "ignored", so its
  | report is never merged with one that measured &&= writes.
  ) do |t|
    decisions = { 'k.rb:2:2' => condition('&&', 16...23, 27...35) }
    counts = { ['k.rb:2:2', 0] => { truthy: 1, falsy: 1 } }
    operands = PathCoverage::Result.new(decisions, counts).operands
    path = "#{t.dir}/path_coverage.json"
    fingerprint = { 'ignored' => ['&&='] }
    PathCoverage::JsonWriter.write(operands, path, fingerprint:)
    actual = JSON.parse(File.read(path))
    assert_equal ['&&='], actual['ignored']
  end

  test 'wdt912', %w(
  | Example: a run measuring methods, its write reached twice,
  | then one that reached nothing
  | Each statement's reaches are written under "reached".
  | One that reached nothing still writes it, empty, so a
  | render knows its statements were never reached.
  ) do |t|
    decisions = { 'k.rb:2:2' => condition('&&', 16...23, 27...35) }
    operands = PathCoverage::Result.new(decisions, {}).operands
    written = [{ 'k.rb:3:4' => 2 }, {}].map.with_index do |reached, i|
      path = "#{t.dir}/#{i}.json"
      PathCoverage::JsonWriter.write(operands, path, reached:)
      JSON.parse(File.read(path))['reached']
    end
    assert_equal [{ 'k.rb:3:4' => 2 }, {}], written
  end
end
