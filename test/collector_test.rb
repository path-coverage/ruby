require_relative 'test_helper'
require 'path_coverage/collector'
require 'path_coverage/post'
require 'json'
require 'open3'
require 'socket'

class CollectorTest < TidTest
  # Its tests listen on ports and spawn a collector, which
  # must not take each other's connections.
  serial!

  test 'CL4k10', %w(
  | the collector saves each JSON report POSTed to it as a
  | file of its own, numbered in the order they arrive,
  | ready to be merged and rendered once every run is done
  ) do |t|
    dir = t.dir
    server = TCPServer.new('127.0.0.1', 0)
    url = "http://127.0.0.1:#{server.addr[1]}/runs"
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    [[2, 0], [0, 1]].each do |truthy, falsy|
      operands = { 'source/kata.rb:3:23' => [{ truthy:, falsy: }] }
      PathCoverage::Post.deliver(operands, url)
    end
    serving.kill
    server.close

    expected = {
      'run-0001.json' => report(2, 0),
      'run-0002.json' => report(0, 1)
    }
    actual = Dir.children(dir).sort.to_h do |name|
      [name, JSON.parse(File.read("#{dir}/#{name}"))]
    end
    assert_equal expected, actual
  end

  test 'CL4k15', %w(
  | a connection that sends no request, eg a check that the
  | collector is up, saves nothing and uses up no number
  ) do |t|
    dir = t.dir
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    TCPSocket.new('127.0.0.1', port).close
    operands = { 'source/kata.rb:3:23' => [{ truthy: 2, falsy: 0 }] }
    PathCoverage::Post.deliver(operands, "http://127.0.0.1:#{port}/")
    serving.kill
    server.close
    actual = Dir.children(dir).to_h do |name|
      [name, JSON.parse(File.read("#{dir}/#{name}"))]
    end
    assert_equal({ 'run-0001.json' => report(2, 0) }, actual)
  end

  test 'CL4k16', %w(
  | Example: a collector saving into a dir that does not exist
  | A report it cannot save is not acknowledged.
  | So the reply to its POST is 500, not 200.
  | A 200 means the report is already saved.
  | The collector says it saved nothing.
  ) do |t|
    dir = "#{t.dir}/missing"
    server = TCPServer.new('127.0.0.1', 0)
    url = "http://127.0.0.1:#{server.addr[1]}/runs"
    collector = PathCoverage::Collector
    # One request, answered as serve answers it, then joined, so
    # the collector has finished before anything is asserted.
    receiving = Thread.new do
      collector.receive(server.accept, dir) do |body|
        collector.save(dir, 'run-0001.json', body)
      end
    end
    operands = { 'source/kata.rb:3:23' => [{ truthy: 2, falsy: 0 }] }
    reply = PathCoverage::Post.deliver(operands, url)
    saved = receiving.value
    server.close
    assert_equal ['500', false], [reply.code, saved]
  end

  test 'CL4k17', %w(
  | Example: a POST with Content-Length 120 whose sender stops
  | after 10 bytes, as when it dies mid-send
  | The body is cut short, so it is not a whole report.
  | Nothing is saved.
  | The reply is 400, not 200.
  ) do |t|
    dir = t.dir
    server = TCPServer.new('127.0.0.1', 0)
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    socket = TCPSocket.new('127.0.0.1', server.addr[1])
    socket.write("POST /runs HTTP/1.1\r\nContent-Length: 120\r\n\r\n")
    socket.write('{"decisions":{')
    socket.close_write
    reply = socket.read
    socket.close
    serving.kill
    server.close
    bad = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
    assert_equal [bad, []], [reply, Dir.children(dir)]
  end

  test 'CL4k18', %w(
  | Example: GET /alive, then a POST of a report
  | The GET is answered 200, with no body.
  | Nothing is saved for it.
  | It uses up no run number, so the report is run-0001.json.
  ) do |t|
    dir = t.dir
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    reply = exchange(port, "GET /alive HTTP/1.1\r\n\r\n")
    operands = { 'source/kata.rb:3:23' => [{ truthy: 2, falsy: 0 }] }
    PathCoverage::Post.deliver(operands, "http://127.0.0.1:#{port}/")
    serving.kill
    server.close
    ok = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    saved = Dir.children(dir).sort
    assert_equal [ok, ['run-0001.json']], [reply, saved]
  end

  test 'CL4k19', %w(
  | Example: GET /ready to a collector whose dir does not exist
  | It cannot save a report.
  | So it is not ready, and the reply is 503.
  ) do |t|
    dir = "#{t.dir}/missing"
    server = TCPServer.new('127.0.0.1', 0)
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    reply = exchange(server.addr[1], "GET /ready HTTP/1.1\r\n\r\n")
    serving.kill
    server.close
    unready = "HTTP/1.1 503 Service Unavailable\r\n" \
              "Content-Length: 0\r\n\r\n"
    assert_equal unready, reply
  end

  test 'CL4k1a', %w(
  | Example: GET /ready to a collector whose dir is writable
  | It can save a report.
  | So it is ready, and the reply is 200.
  | Nothing is saved for it.
  ) do |t|
    dir = t.dir
    server = TCPServer.new('127.0.0.1', 0)
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    reply = exchange(server.addr[1], "GET /ready HTTP/1.1\r\n\r\n")
    serving.kill
    server.close
    ok = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    assert_equal [ok, []], [reply, Dir.children(dir)]
  end

  test 'CL4k1c', %w(
  | Example: GET /ready to a collector whose dir exists but is
  | read-only
  | It cannot save a report.
  | So it is not ready, and the reply is 503.
  ) do |t|
    dir = "#{t.dir}/read_only"
    FileUtils.mkdir_p(dir)
    File.chmod(0o555, dir)
    server = TCPServer.new('127.0.0.1', 0)
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    reply = exchange(server.addr[1], "GET /ready HTTP/1.1\r\n\r\n")
    serving.kill
    server.close
    unready = "HTTP/1.1 503 Service Unavailable\r\n" \
              "Content-Length: 0\r\n\r\n"
    assert_equal unready, reply
  ensure
    File.chmod(0o755, dir)
  end

  test 'CL4k1b', %w(
  | Example: a collector waiting for a connection, whose server
  | is then closed
  | serve returns.
  | It does not raise.
  ) do |t|
    dir = t.dir
    server = TCPServer.new('127.0.0.1', 0)
    collector = PathCoverage::Collector
    serving = Thread.new { collector.serve(server, dir) }
    50.times do
      break if serving.status == 'sleep'

      sleep(0.01)
    end
    server.close
    assert_same serving, serving.join(5)
  end

  test 'CL4k20', %w(
  | the collector command's -h prints its usage, with an
  | example, and exits 0
  ) do
    stdout, stderr, status = Open3.capture3(*command('-h'))
    assert_equal ['', 0], [stderr, status.exitstatus]
    name = 'path_coverage_collector'
    assert_includes stdout, "Usage: #{name} PORT DIR"
    assert_includes stdout, "#{name} 4570 "
  end

  test 'CL4k30', %w(
  | Example: path_coverage_collector PORT DIR, sent one report,
  | then TERM while waiting for the next
  | It creates DIR.
  | It saves the report in DIR as run-0001.json.
  | On TERM it exits 0, printing nothing.
  ) do |t|
    dir = "#{t.dir}/runs"
    probe = TCPServer.new('127.0.0.1', 0)
    port = probe.addr[1]
    probe.close
    err = "#{t.dir}/stderr"
    pid = Process.spawn(*command(port.to_s, dir), err:)
    wait_until_listening(port)
    operands = { 'source/kata.rb:3:23' => [{ truthy: 1, falsy: 1 }] }
    PathCoverage::Post.deliver(operands, "http://127.0.0.1:#{port}/")
    Process.kill('TERM', pid)
    _, status = Process.wait2(pid)
    saved = JSON.parse(File.read("#{dir}/run-0001.json"))
    stderr = File.read(err)
    actual = [saved, status.exitstatus, stderr]
    assert_equal [report(1, 1), 0, ''], actual
  end

  test 'CL4k31', %w(
  | Example: the collector command is sent TERM while half of
  | a report's body has arrived
  | It stops accepting new connections.
  | It still finishes the report in hand.
  | The report is saved and answered 200.
  | Then the command exits 0.
  ) do |t|
    dir = t.dir
    probe = TCPServer.new('127.0.0.1', 0)
    port = probe.addr[1]
    probe.close
    pid = Process.spawn(*command(port.to_s, dir))
    wait_until_listening(port)
    body = JSON.generate(report(1, 1))
    half = body.size / 2
    socket = TCPSocket.new('127.0.0.1', port)
    head = "POST / HTTP/1.1\r\nContent-Length: #{body.size}\r\n\r\n"
    socket.write(head)
    socket.write(body[0...half])
    # The collector cannot say when it has accepted, so wait.
    sleep(0.2)
    Process.kill('TERM', pid)
    sleep(0.2)
    socket.write(body[half..])
    socket.close_write
    reply = socket.read
    socket.close
    _, status = Process.wait2(pid)
    ok = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    saved = JSON.parse(File.read("#{dir}/run-0001.json"))
    actual = [reply, saved, status.exitstatus]
    assert_equal [ok, report(1, 1), 0], actual
  end

  # The collector command, with args, run from this checkout.
  def command(*args)
    root = File.expand_path('..', __dir__)
    exe = "#{root}/exe/path_coverage_collector"
    ['ruby', "-I#{root}/lib", exe, *args]
  end

  # Returns once something accepts connections on port.
  def wait_until_listening(port)
    50.times do
      TCPSocket.new('127.0.0.1', port).close
      return
    rescue Errno::ECONNREFUSED
      sleep(0.1)
    end
  end

  # Sends request to port on a connection of its own, closes
  # its writing side, and returns the whole reply.
  def exchange(port, request)
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write(request)
    socket.close_write
    reply = socket.read
    socket.close
    reply
  end

  # The parsed JSON report of one operand of one decision, from a
  # run measuring every kind.
  def report(truthy, falsy)
    counts = { 'truthy' => truthy, 'falsy' => falsy }
    {
      '$schema' => PathCoverage::JsonWriter::SCHEMA,
      'decisions' => { 'source/kata.rb:3:23' => [counts] },
      'kinds' => %w(block case chain choice contains safe write),
      'measured_by' => PathCoverage::MeasuredBy.versions
    }
  end
end
