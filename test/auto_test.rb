require_relative 'test_helper'
require 'path_coverage/collector'
require 'path_coverage/kernel'
require 'path_coverage/manifest'
require 'json'
require 'open3'
require 'socket'
require 'tmpdir'

class AutoTest < TidTest
  # One of its tests requires auto in this process, which
  # reads the configuration of the one global load hook.
  serial!

  test 'Au7x20', %w(
  | with no collector in the environment, requiring auto
  | starts nothing and prints nothing, so an image can set
  | RUBYOPT for every run while only some are measured
  ) do
    assert_nil ENV.fetch('PATH_COVERAGE_COLLECTOR', nil)
    before = PathCoverage.config
    assert_output('', '') { require 'path_coverage/auto' }
    # equal? as before is nil when no test has started yet.
    assert before.equal?(PathCoverage.config), 'config changed'
  end

  test 'Au7x10', %w(
  | requiring path_coverage/auto, as RUBYOPT=-r does,
  | with the settings in the environment, covers a script
  | that exits 42 and POSTs its counts to the collector,
  | leaving its stdout, stderr and exit status unchanged
  ) do |t|
    source = <<~RUBY
      module KataAu7x10
        def self.kata?(id) = !id.empty? && id.start_with?('K')
      end
    RUBY
    t.write(source, 'source/kata.rb')
    t.write(<<~RUBY, 'run.rb')
      require_relative 'source/kata'
      KataAu7x10.kata?('Kp9sA2')
      exit 42
    RUBY
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    received = Thread.new { request_body(server.accept) }
    env = {
      'PATH_COVERAGE_ROOT' => t.dir,
      'PATH_COVERAGE_COVER' => 'source/**/*.rb',
      'PATH_COVERAGE_DIR' => "#{t.dir}/condition",
      'PATH_COVERAGE_COLLECTOR' => "http://127.0.0.1:#{port}/runs"
    }
    lib = File.expand_path('../lib', __dir__)
    auto = '-rpath_coverage/auto'
    command = ['ruby', "-I#{lib}", auto, "#{t.dir}/run.rb"]
    stdout, stderr, status = Open3.capture3(env, *command)
    assert_equal ['', '', 42], [stdout, stderr, status.exitstatus]

    path = 'source/kata.rb'
    decisions = PathCoverage::Manifest.decisions(source, path)
    expected = {
      decisions.keys.first => [
        { 'truthy' => 1, 'falsy' => 0 },
        { 'truthy' => 1, 'falsy' => 0 }
      ]
    }
    assert_equal expected,
                 JSON.parse(received.join(5).value)['decisions']
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
