require_relative 'test_helper'
require 'open3'

class ProjectsTest < TidTest
  test '4WXv10', %w(
  | a project run with path coverage started prints,
  | as it exits, a line for each path through an && its run
  | never took
  ) do |t|
    stdout, stderr, status = run_project('single_and', t.dir)
    expected = [
      'source/kata.rb:3:23 path never taken: ' \
      "`ok?(id)` true, `id.start_with?('N')` false",
      'source/kata.rb:4:24 never reached'
    ].join("\n")
    assert_equal "#{expected}\n", stdout
    assert_equal '', stderr
    assert status.success?
  end

  test '4WXv20', %w(
  | Example: the nested_conditions project's kata.rb
  | It has || decisions, chains, and nested and grouped conditions.
  | It has an any? wholly an operand of an ||, so a decision of its
  | own, with a decision inside its block, a new scope.
  | It has an and whose operand is a command call.
  | All of them run unchanged when instrumented.
  | Their paths never taken are listed in source order.
  ) do |t|
    stdout, stderr, status = run_project('nested_conditions', t.dir)
    never = 'path never taken:'
    any = "source/kata.rb:17:8 #{never} `ids`"
    block = '`ok?(id) && id.size == 2`'
    call = '`ids.any? { |id| ok?(id) && id.size == 2 }`'
    expected = [
      "source/kata.rb:5:4 #{never} " \
      "`id.start_with?('N')` false, `id.size == 6` false",
      "source/kata.rb:9:4 #{never} " \
      '`ok?(id)` true, `id.size > 1` true, `id.size < 9` false',
      "source/kata.rb:9:4 #{never} " \
      '`ok?(id)` true, `id.size > 1` false',
      "source/kata.rb:13:4 #{never} `ok?(id)` true, " \
      "`id.start_with?('G')` false, `id.end_with?('G')` true",
      "source/kata.rb:13:4 #{never} `ok?(id)` true, " \
      "`id.start_with?('G')` false, `id.end_with?('G')` false",
      "source/kata.rb:17:4 #{never} " \
      "#{call} false, `ids.empty?` false",
      "#{any} 1 item, #{block} false",
      "#{any} 2+ items, #{block} true",
      "#{any} 2+ items, #{block} false",
      "source/kata.rb:17:20 #{never} " \
      '`ok?(id)` true, `id.size == 2` false',
      "source/kata.rb:17:20 #{never} `ok?(id)` false",
      "source/kata.rb:21:4 #{never} " \
      "`ok?(id)` true, `id.include? 'N'` false"
    ].join("\n")
    assert_equal "#{expected}\n", stdout
    assert_equal '', stderr
    assert status.success?
  end

  test '4WXv30', %w(
  | Example: the multiline_condition project, run with
  | CONDITIONS off and then on
  | An instrumented file has the same relevant lines for
  | line coverage as it has uninstrumented.
  | So SimpleCov's line totals do not change.
  | That holds for a condition written over several lines.
  | It holds for a method whose paths are measured, with a
  | modifier if among its decisions.
  ) do |t|
    off, on = %w(off on).map do |conditions|
      dir = "#{t.dir}/#{conditions}"
      FileUtils.mkdir_p(dir)
      env = { 'CONDITIONS' => conditions }
      run_project('multiline_condition', dir, env).first
    end
    assert_equal off, on
  end

  test '4WXv40', %w(
  | Example: total -= 10 if order.fetch(:total) > 100 && ...
  | The project measures methods too.
  | It prints its decision gaps.
  | The modifier if's decision is named at its keyword (5:16), and
  | took both its paths; its predicate's && is a decision of its
  | own, named where it starts (5:19), with one gap.
  | fee still runs unchanged when instrumented.
  ) do |t|
    stdout, stderr, status = run_project('two_decisions', t.dir)
    expected = [
      'source/shop.rb:5:19 path never taken: ' \
      '`order.fetch(:total) > 100` true, `order.fetch(:paid)` false'
    ].join("\n")
    assert_equal "#{expected}\n", stdout
    assert_equal '', stderr
    assert status.success?
  end

  private

  # Runs test/projects/name/run.rb in its own ruby process,
  # with env added to its environment and its coverage written
  # into dir, returning its stdout, stderr and exit status.
  def run_project(name, dir, env = {})
    run_rb = File.expand_path("projects/#{name}/run.rb", __dir__)
    lib = File.expand_path('../lib', __dir__)
    env = env.merge('COVERAGE_DIR' => dir)
    Open3.capture3(env, 'ruby', '-I', lib, run_rb)
  end
end
