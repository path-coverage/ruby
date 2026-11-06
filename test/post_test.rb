require_relative 'test_helper'
require 'path_coverage/collector'
require 'path_coverage/configuration'
require 'path_coverage/manifest'
require 'path_coverage/render'
require 'json'
require 'socket'
require 'tmpdir'

class PostTest < TidTest
  # Its tests capture $stdout, which is process-wide.
  serial!

  test 'Pq3s10', %w(
  | with report :post the operands are POSTed as the JSON
  | report to the collector url, printing nothing, so a run
  | whose stdout and stderr are checked exactly is unchanged
  ) do |t|
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    received = Thread.new { request_body(server.accept) }
    operands = {
      'source/kata.rb:3:23' => [
        { truthy: 2, falsy: 1 },
        { truthy: 1, falsy: 0, only: :truthy }
      ]
    }
    config = post_config(t.dir, "http://127.0.0.1:#{port}/runs")
    assert_output('', '') do
      PathCoverage::Render.run(operands, {}, config)
    end
    expected = {
      '$schema' => PathCoverage::JsonWriter::SCHEMA,
      'decisions' => {
        'source/kata.rb:3:23' => [
          { 'truthy' => 2, 'falsy' => 1 },
          { 'truthy' => 1, 'falsy' => 0, 'only' => 'truthy' }
        ]
      },
      'kinds' => %w(block case chain choice contains safe write)
    }
    assert_equal expected, JSON.parse(received.join(5).value)
  end

  test 'Pq3s11', %w(
  | the decision paths are POSTed in the JSON report too, each
  | leaf's span with them, so a collector's render shows
  | every path each decision took
  ) do |t|
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    received = Thread.new { request_body(server.accept) }
    source = "def fee(u) = u ? 5 : 7\n"
    decisions = PathCoverage::Manifest.decisions(source, 'fee.rb')
    files = { '/app/fee.rb' => { source:, decisions: } }
    decision = 'fee.rb:1:15'
    assert_equal [decision], decisions.keys
    operands = { decision => [{ truthy: 1, falsy: 1 }] }
    taken = [{ path: [true], count: 1 }, { path: [false], count: 1 }]
    decision_paths = { decision => taken }
    config = post_config(t.dir, "http://127.0.0.1:#{port}/runs")
    render = PathCoverage::Render
    assert_output('', '') do
      render.run(operands, files, config, decision_paths:)
    end
    expected = {
      decision => {
        'leaves' => [%w(1:13 1:14)],
        'taken' => [
          { 'path' => [true], 'count' => 1 },
          { 'path' => [false], 'count' => 1 }
        ]
      }
    }
    json = JSON.parse(received.join(5).value)
    assert_equal expected, json['paths']
  end

  test 'Pq3s12', %w(
  | Example: a run with ignore '&&=' and report :post
  | The POSTed report names &&= as ignored, so a collector's
  | render refuses to merge it with a run measuring &&= writes.
  ) do |t|
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    received = Thread.new { request_body(server.accept) }
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      collector "http://127.0.0.1:#{port}/runs"
      report :post
      ignore '&&='
    end
    operands = { 'source/kata.rb:3:23' => [{ truthy: 1, falsy: 0 }] }
    assert_output('', '') do
      PathCoverage::Render.run(operands, {}, config)
    end
    json = JSON.parse(received.join(5).value)
    assert_equal ['&&='], json['ignored']
  end

  test 'Pq3s13', %w(
  | Example: report :gaps, :post
  | The gaps are printed and the report is POSTed too, as each
  | reporter chosen runs.
  ) do |t|
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    received = Thread.new { request_body(server.accept) }
    config = PathCoverage::Configuration.new do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      collector "http://127.0.0.1:#{port}/runs"
      report :gaps, :post
    end
    operands = { 'source/kata.rb:3:23' => [{ truthy: 0, falsy: 0 }] }
    assert_output("source/kata.rb:3:23 never reached\n", '') do
      PathCoverage::Render.run(operands, {}, config)
    end
    decisions = JSON.parse(received.join(5).value)['decisions']
    assert_equal ['source/kata.rb:3:23'], decisions.keys
  end

  test 'Pq3s20', %w(
  | a collector that cannot be reached is passed over in
  | silence, so a run without one still exits as it would
  ) do |t|
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    config = post_config(t.dir, "http://127.0.0.1:#{port}/runs")
    operands = { 'source/kata.rb:3:23' => [{ truthy: 1, falsy: 0 }] }
    assert_output('', '') do
      PathCoverage::Render.run(operands, {}, config)
    end
  end

  test 'Pq3s30', %w(
  | a collector that accepts the connection but never
  | answers is given up on within two seconds, so it
  | cannot hang the run that is exiting
  ) do |t|
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    config = post_config(t.dir, "http://127.0.0.1:#{port}/runs")
    operands = { 'source/kata.rb:3:23' => [{ truthy: 1, falsy: 0 }] }
    started = now
    assert_output('', '') do
      PathCoverage::Render.run(operands, {}, config)
    end
    elapsed = now - started
    server.close
    assert elapsed < 2, "took #{elapsed.round(1)}s"
  end

  test 'Pq3s40', %w(
  | an http_proxy in the environment, as a docker build
  | often has, is not used, since the collector is local
  | to the build and a proxy would not reach it
  ) do |t|
    dead = TCPServer.new('127.0.0.1', 0)
    dead_port = dead.addr[1]
    dead.close
    # Not loopback, which Net::HTTP never proxies anyway.
    host = Socket.ip_address_list.find(&:ipv4_private?).ip_address
    server = TCPServer.new(host, 0)
    port = server.addr[1]
    received = Thread.new { request_body(server.accept) }
    config = post_config(t.dir, "http://#{host}:#{port}/runs")
    operands = { 'source/kata.rb:3:23' => [{ truthy: 1, falsy: 0 }] }
    with_env('http_proxy', "http://127.0.0.1:#{dead_port}") do
      PathCoverage::Render.run(operands, {}, config)
    end
    decisions = JSON.parse(received.join(3).value)['decisions']
    assert_equal ['source/kata.rb:3:23'], decisions.keys
  end

  # Seconds on the monotonic clock, for timing a call.
  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Runs the block with ENV[name] set to value, then
  # restores it.
  def with_env(name, value)
    saved = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    ENV[name] = saved
  end

  # A configuration choosing only :post, to url, rooted and
  # reporting in dir.
  def post_config(dir, url)
    PathCoverage::Configuration.new do
      root dir
      cover '*.rb'
      coverage_dir dir
      collector url
      report :post
    end
  end

  # The body of the one HTTP request on client, after
  # answering it 200, read as the collector reads it.
  def request_body(client)
    body = nil
    collector = PathCoverage::Collector
    collector.receive(client, Dir.tmpdir) { |sent| body = sent }
    body
  end
end
