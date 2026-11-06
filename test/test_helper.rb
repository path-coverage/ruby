require 'English'
require 'path_coverage/condition'
require 'etc'
require 'minitest/autorun'
require 'minitest/reporters'
require_relative 'tid_fixture'

Minitest.parallel_executor =
  Minitest::Parallel::Executor.new(Etc.nprocessors)
Minitest::Reporters.use!(
  [Minitest::Reporters::DefaultReporter.new]
)

# Base class whose tests are named by a unique tid, a test id of
# id58 characters, so a run can be narrowed to the tids given on
# the command line.
class TidTest < Minitest::Test
  parallelize_me!

  # Opts a class out of parallel running, for tests that swap
  # process-wide state ($stdout, ENV, a global hook). Both of
  # the class methods parallelize_me! added are undone: the
  # ordering, and run, which would still send each test to the
  # thread pool.
  def self.serial!
    singleton_class.define_method(:run_order) { :random }
    singleton_class.define_method(:run) do |klass, name, reporter|
      Minitest::Runnable.run(klass, name, reporter)
    end
  end

  ARGS = (ARGV.sort.uniq - ['--']).freeze # eg 2m4

  @seen_tids = []
  singleton_class.attr_reader :seen_tids

  # The tid fragments given on the command line; a subclass can
  # override it.
  def self.args
    ARGS
  end

  # Defines a test only when no tids were given on the command
  # line, or one of them is part of its tid.
  def self.test(tid, *lines, &body)
    tid = checked_tid(tid, lines)
    return unless selected?(tid)

    description = described(lines)
    file = File.basename(body.source_location[0])
    define_method(test_name(tid, description)) do
      run_tid_test(tid, description, file, body)
    end
  end

  # The description as written: each word that is exactly |
  # starts a new line, so a || stays a word.
  def self.described(lines)
    words = lines.join(' ').split
    bar_lines = words.slice_before('|').map { |line| line.join(' ') }
    bar_lines.join("\n")
  end

  # True when no tids were given, or one is in tid.
  def self.selected?(tid)
    args.empty? || tid.match?(Regexp.union(args))
  end

  # The name Minitest reports, tid and words included.
  def self.test_name(tid, description)
    :"test_\nid='#{tid}'\n#{description}"
  end

  # Leaves out i I l o O, which read too like 1 and 0.
  TID_ALPHABET = %w(
    0 1 2 3 4 5 6 7 8 9
    A B C D E F G H J K L M N P Q R S T U V W X Y Z
    a b c d e f g h j k m n p q r s t u v w x y z
  ).join.freeze

  # True when str is a string of TID_ALPHABET's characters only.
  # An empty one is refused before this is asked.
  def self.tid?(str)
    str.is_a?(String) && str.match?(/\A[#{TID_ALPHABET}]+\z/)
  end

  # Returns tid, or raises naming what is wrong with it or with
  # its description.
  def self.checked_tid(tid, lines)
    problem = tid_problem(tid) || description_problem(lines)
    raise tid_error(problem, tid, lines) if problem

    TidTest.seen_tids << tid
    tid
  end

  # Returns why tid cannot name a test, or nil if it can.
  def self.tid_problem(tid)
    return 'empty' if tid == ''
    return 'not a tid' unless tid?(tid)

    'duplicate' if TidTest.seen_tids.include?(tid)
  end

  # Why the description cannot be used, or nil if it can.
  def self.description_problem(lines)
    return if lines.join(' ').split.first == '|'

    'description lines must start with |'
  end

  # A message with a ! pointing at the offending tid.
  def self.tid_error(problem, tid, lines)
    method = "test '#{tid}',"
    pointer = "#{' ' * method.index("'")}!"
    words = "'#{lines.join(' ')}'"
    parts = ["#{pointer}#{problem}", pointer, method, words]
    "\n\n#{parts.join("\n")}\n\n"
  end

  # Runs body as this test, between the setup and teardown
  # hooks, given its TidFixture, t; teardown runs, and t's dir
  # goes, even when body fails.
  def run_tid_test(tid, description, file, body)
    show_test_id(tid, file)
    fixture = TidFixture.new(tid, description)
    tid_setup
    begin
      instance_exec(fixture, &body)
    ensure
      report_error
      fixture.remove
      tid_teardown
    end
  end

  # Prints tid and its file when SHOW_TEST_IDS=true.
  def show_test_id(tid, file)
    return unless ENV['SHOW_TEST_IDS'] == 'true'

    p "#{tid}:#{file}"
  end

  # Prints the message of the error the body raised.
  def report_error
    puts $ERROR_INFO.message unless $ERROR_INFO.nil?
  end

  # A site's condition as the manifest finds it, eg
  # condition('&&', 16...23, 27...35), with commands naming
  # the leaves that are command calls, fixed the leaves that
  # can have one outcome only, and extent the byte range of the
  # whole condition.
  def condition(
    operator, *operands, commands: [], fixed: {}, extent: nil
  )
    PathCoverage::Condition.new(
      operator:, operands:, commands:, fixed:, extent:
    )
  end

  # One arm of a ternary as the manifest finds it, eg
  # arm(:then, 26...50, both): kind is :then or :else, extent
  # its byte range, and body the condition it holds, nil for a
  # plain value.
  def arm(kind, extent, body = nil)
    PathCoverage::Arm.new(kind:, extent:, body:)
  end

  # Hook for subclasses; runs before each test body.
  def tid_setup; end

  # Hook for subclasses; runs after each test body.
  def tid_teardown; end
end
