require_relative 'test_helper'

class TestHelperTest < TidTest
  # Its tests capture $stdout and set ENV['SHOW_TEST_IDS'].
  serial!

  # The body of a throwaway test that is defined, never run.
  NO_OP = proc { :no_op }

  test 'Fb7A05', %w(
  | a class that calls serial! opts out of parallel running
  | on both counts: it is ordered with the serial suites,
  | and its tests are run in place, not sent to the pool
  ) do
    klass = Class.new(TidTest) { serial! }
    assert_equal :random, klass.run_order

    assert_equal klass.singleton_class, klass.method(:run).owner
  end

  test 'Fb7A10', %w(
  | a running test can read its own tid and description
  ) do |t|
    assert_equal 'Fb7A10', t.id

    words = '| a running test can read its own tid and description'
    assert_equal words, t.description
  end

  test 'Fb7B10', %w(
  | Example: a test that asks for t.dir twice, then raises
  | t.dir is one directory, named for the test's tid, made as it
  | is first asked for. It is removed once the test ends, even as
  | the test raises, so no test leaves a fixture behind.
  ) do
    seen = []
    klass = Class.new(TidTest) do
      test('Fb7Bx1', %w(| kata exists)) do |t|
        seen.push(t.dir, t.dir, File.directory?(t.dir))
        raise 'disk full'
      end
    end
    name = klass.public_instance_methods(false)[0]
    assert_output("disk full\n") do
      assert_raises(RuntimeError) { klass.new(name).send(name) }
    end
    dir, again, made = seen
    assert_equal [dir, true], [again, made]
    assert_includes File.basename(dir), 'Fb7Bx1'
    refute File.exist?(dir)
  end

  test 'Fb7B20', %w(
  | Example: t.write of module Fee holding fee, then t.load
  | t.write writes the source to t.file, fixture.rb, in t.dir.
  | t.load loads it wrapped in a module of its own, which it
  | returns, so a fixture's constants never meet another's.
  ) do |t|
    source = "module Fee\n  def self.fee = 5\nend\n"
    t.write(source)
    assert_equal 'fixture.rb', t.file
    assert_equal source, File.read("#{t.dir}/#{t.file}")
    wrap = t.load
    assert_equal 5, wrap::Fee.fee
    assert wrap.const_defined?(:Fee, false)
  end

  test 'Fb7B30', %w(
  | Example: t.write of RATE = a ?: on ENV, t.start with group
  | 'all', t.load, then t.report, with no RATE set
  | t.start starts path_coverage covering t.dir's .rb files,
  | reporting into t.dir, any settings of its block added.
  | t.report runs the report the process's exit would. t.json is
  | the JSON report it wrote: the ?:'s else taken once, and the
  | group's totals.
  ) do |t|
    t.write("RATE = ENV.key?('RATE_Fb7B30') ? 2 : 1\n")
    t.start { group 'all', '*.rb' }
    t.load
    assert_output(/path never taken/) { t.report }
    taken = t.json['paths']["#{t.file}:1:31"]['taken']
    assert_equal([0, 1], taken.map { _1['count'] })
    assert_equal ['all'], t.json['totals']['groups'].keys
  end

  test 'Fb7B40', %w(
  | Example: t.write of module Kata as source/kata.rb, then
  | t.load of it
  | A named file keeps its name, in its folder, made as it is
  | written, so a test can lay out a tree of files.
  ) do |t|
    source = "module Kata\n  def self.ok? = true\nend\n"
    t.write(source, 'source/kata.rb')
    assert File.exist?("#{t.dir}/source/kata.rb")
    assert t.load('source/kata.rb')::Kata.ok?
  end

  test 'Fb7B50', %w(
  | Example: t.start with no block, then t.report, with nothing
  | loaded
  | With no more settings, path_coverage covers t.dir's .rb files,
  | prints its gaps, of which there are none, and writes its JSON
  | report into t.dir.
  ) do |t|
    t.write("RATE = 1\n")
    t.start
    assert_output('', '') { t.report }
    assert_nil t.json['paths']
  end

  test 'Fb7A15', %w(
  | a description written as bar lines keeps those lines,
  | so a report shows it as written
  ) do
    words = %w(
      | POST /kata_create(manifest)
      | has status 200
    )
    seen = nil
    klass = Class.new(TidTest) do
      test('Fb7Ax1', words) { |t| seen = t.description }
    end
    name = klass.public_instance_methods(false)[0]
    klass.new(name).send(name)
    expected = "| POST /kata_create(manifest)\n| has status 200"
    assert_equal expected, seen
  end

  test 'Fb7A17', %w(
  | a || inside a bar line is a word, not two line breaks,
  | so a description can talk about the operator
  ) do
    words = %w(
      | ok? || new? is recorded
      | operand by operand
    )
    seen = nil
    klass = Class.new(TidTest) do
      test('Fb7Ax2', words) { |t| seen = t.description }
    end
    name = klass.public_instance_methods(false)[0]
    klass.new(name).send(name)
    expected = [
      '| ok? || new? is recorded',
      '| operand by operand'
    ].join("\n")
    assert_equal expected, seen
  end

  test 'Fb7A18', %w(
  | the name a failure reports puts every bar line
  | in the same column, so the description reads as written
  ) do
    words = "| POST /kata_create(manifest)\n| has status 200"
    expected = [
      'test_',
      "id='Fb7Ax8'",
      '| POST /kata_create(manifest)',
      '| has status 200'
    ].join("\n").to_sym
    actual = TidTest.test_name('Fb7Ax8', words)
    assert_equal expected, actual
  end

  test 'Fb7A20', %w(
  | an empty tid is refused, pointing at the offending test
  ) do
    error = assert_raises(RuntimeError) do
      Class.new(TidTest) { test('', %w(| kata exists), &NO_OP) }
    end
    expected = [
      '',
      '',
      '     !empty',
      '     !',
      "test '',",
      "'| kata exists'",
      '',
      ''
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'Fb7A30', %w(
  | a tid using a letter outside the alphabet is refused
  ) do
    error = assert_raises(RuntimeError) do
      Class.new(TidTest) do
        test('Fb7AO1', %w(| kata exists), &NO_OP)
      end
    end
    expected = [
      '',
      '',
      '     !not a tid',
      '     !',
      "test 'Fb7AO1',",
      "'| kata exists'",
      '',
      ''
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'Fb7A32', %w(
  | a tid using a lowercase l, which reads too like 1, is
  | refused
  ) do
    assert_raises(RuntimeError) do
      Class.new(TidTest) do
        test('Fb7Al1', %w(| kata exists), &NO_OP)
      end
    end
  end

  test 'Fb7A31', %w(
  | Example: a test whose tid is the number 7105
  | A tid that is not a string is refused, as no number or
  | symbol can be a tid.
  ) do
    error = assert_raises(RuntimeError) do
      Class.new(TidTest) { test(7105, %w(| kata exists), &NO_OP) }
    end
    assert_includes error.message, '!not a tid'
  end

  test 'Fb7A35', %w(
  | a description not written as bar lines is refused,
  | so every failure report shows its lines as written
  ) do
    error = assert_raises(RuntimeError) do
      Class.new(TidTest) do
        test('Fb7Ax3', %w(kata exists), &NO_OP)
      end
    end
    expected = [
      '',
      '',
      '     !description lines must start with |',
      '     !',
      "test 'Fb7Ax3',",
      "'kata exists'",
      '',
      ''
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'Fb7A40', %w(
  | a tid already used by another test is refused
  ) do
    error = assert_raises(RuntimeError) do
      Class.new(TidTest) do
        test('Fb7Ax4', %w(| kata exists), &NO_OP)
        test('Fb7Ax4', %w(| kata missing), &NO_OP)
      end
    end
    expected = [
      '',
      '',
      '     !duplicate',
      '     !',
      "test 'Fb7Ax4',",
      "'| kata missing'",
      '',
      ''
    ].join("\n")
    assert_equal expected, error.message
  end

  test 'Fb7A50', %w(
  | a test whose tid contains none of the command-line args
  | is not defined
  ) do
    klass = Class.new(TidTest) do
      def self.args = ['Kp9']
      test('Fb7Ax5', %w(| kata exists), &NO_OP)
    end
    assert_equal [], klass.public_instance_methods(false)
  end

  test 'Fb7A51', %w(
  | Example: runs narrowed to Fb7, to Kp9 and Fb7, and to Kp9
  | and Zz9, each with a test whose tid starts Fb7
  | A test is defined when one of the args is part of its tid,
  | however many args there are, and not when none is.
  ) do
    cases = { 'Fb7Ay1' => %w(Fb7), 'Fb7Ay2' => %w(Kp9 Fb7),
              'Fb7Ay3' => %w(Kp9 Zz9) }
    defined = cases.map do |tid, args|
      klass = Class.new(TidTest) do
        define_singleton_method(:args) { args }
        test(tid, %w(| kata exists), &NO_OP)
      end
      klass.public_instance_methods(false).size
    end
    assert_equal [1, 1, 0], defined
  end

  test 'Fb7A60', %w(
  | with SHOW_TEST_IDS=true a test prints its tid and file
  | before running
  ) do
    klass = Class.new(TidTest) do
      test('Fb7Ax6', %w(| kata exists), &NO_OP)
    end
    name = klass.public_instance_methods(false)[0]
    ENV['SHOW_TEST_IDS'] = 'true'
    expected = "\"Fb7Ax6:test_helper_test.rb\"\n"
    assert_output(expected) { klass.new(name).send(name) }
  ensure
    ENV.delete('SHOW_TEST_IDS')
  end

  test 'Fb7A70', %w(
  | a test that raises prints the error's message,
  | then re-raises it
  ) do
    klass = Class.new(TidTest) do
      test('Fb7Ax7', %w(| kata exists)) { raise 'disk full' }
    end
    name = klass.public_instance_methods(false)[0]
    assert_output("disk full\n") do
      assert_raises(RuntimeError) { klass.new(name).send(name) }
    end
  end
end
