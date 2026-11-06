require_relative 'test_helper'
require 'path_coverage/kernel'
require 'path_coverage/manifest'
require 'path_coverage/decision_paths'

class FoldMatrixTest < TidTest
  # Its test swaps the configuration of the one global load
  # hook.
  serial!

  # Each kind of decision, as an expression over a, b, ids and u.
  KINDS = {
    '&&' => 'a && b',
    '||' => 'a || b',
    '?:' => '(a ? b : nil)',
    'case' => '(case a when 1 then b end)',
    'any?' => 'ids.any? { |i| i.odd? }',
    'all?' => 'ids.all? { |i| i.odd? }',
    'none?' => 'ids.none? { |i| i.odd? }',
    'find_index' => 'ids.find_index { |i| i.odd? }',
    'take_while' => 'ids.take_while { |i| i.odd? }',
    'find' => 'ids.find { |i| i.odd? }',
    'select' => 'ids.select { |i| i.odd? }',
    '&.' => 'u&.name',
    '||=' => '(@m ||= a)'
  }.freeze

  # Each place one expression can sit in another, X marking it.
  POSITIONS = {
    'operand' => '(X) && c',
    'predicate' => '(X) ? 1 : 2',
    'if' => "if X\n    1\n  else\n    2\n  end",
    'receiver' => '(X).to_s.empty? && c',
    'argument' => 'c.equal?(X) && c',
    'arm' => 'c ? (X) : 2'
  }.freeze

  # Every input each method is called with.
  VALUES = [nil, true, 1].freeze
  IDS = [[], [1], [2], [1, 2]].freeze

  test 'Fm7k01', %w(
  | Example: a && b as the operand of (X) && c, and every other
  | kind of decision in every other position
  | One expression is one decision, whatever decisions nest in it and
  | wherever they sit; but for a block method's call whose value
  | follows from its path, eg any?, that is wholly an operand,
  | a predicate, an if's test or a ?:'s arm, and an && or || that
  | is wholly a predicate or an if's test: each is a decision of its
  | own, so two.
  | The rewritten code returns what the uninstrumented code does.
  | Every path recorded is one of the decision's possible paths.
  ) do |t|
    named = Struct.new(:name)
    users = [nil, named.new('kim')]
    cases = KINDS.flat_map do |kind, expression|
      POSITIONS.map do |position, outer|
        [kind, position, outer.sub('X', expression)]
      end
    end
    cases.each_with_index do |(_, _, body), index|
      t.write(source('M', body), "m#{index}.rb")
    end
    t.start # this test reads the recorder
    inputs = VALUES.product(VALUES, VALUES, IDS, users)
    actual = cases.each_with_index.map do |(kind, position, body), i|
      file = "m#{i}.rb"
      covered = t.load(file)::M
      plain = source("Plain#{i}", body)
      eval(plain, TOPLEVEL_BINDING) # rubocop:disable Security/Eval
      same = inputs.map { covered.m(*_1) } ==
             inputs.map { call("Plain#{i}", _1) }
      mine = source('M', body)
      decisions = PathCoverage::Manifest.decisions(mine, file)
      impossible = decisions.flat_map do |decision, condition|
        PathCoverage.recorder.decision_paths[decision].keys -
          PathCoverage::DecisionPaths.possible(condition)
      end
      ["#{kind} as #{position}", decisions.size, same, impossible]
    end
    expected = cases.map do |kind, position, _|
      own = OWN.fetch(kind, []).include?(position)
      ["#{kind} as #{position}", own ? 2 : 1, true, []]
    end
    assert_equal expected, actual
  end

  # The positions where an expression is wholly a leaf or an arm.
  WHOLE = %w(operand predicate if arm).freeze

  # The positions where an expression is wholly a predicate.
  TESTS = %w(predicate if).freeze

  # { kind => the positions where it is a decision of its own }.
  OWN = {
    **%w(any? all? none? find_index take_while select).to_h do |kind|
      [kind, WHOLE]
    end,
    '&&' => TESTS, '||' => TESTS
  }.freeze

  test 'Fm7k02', %w(
  | Example: a && b as the operand of (X) && c, with && ignored,
  | and every other kind of decision in every other position, with
  | that kind ignored
  | No decision measures the ignored operator, at its top or
  | nested in it.
  | The rewritten code returns what the uninstrumented code does.
  | Every path recorded is one of the decision's possible paths.
  ) do |t|
    named = Struct.new(:name)
    users = [nil, named.new('kim')]
    cases = KINDS.flat_map do |kind, expression|
      POSITIONS.map do |position, outer|
        [kind, position, outer.sub('X', expression)]
      end
    end
    inputs = VALUES.product(VALUES, VALUES, IDS, users)
    actual = cases.each_with_index.map do |(kind, position, body), i|
      file = "ig#{i}.rb"
      t.write(source('M', body), file)
      on_exit = ->(&_report) {} # this test reads the recorder
      PathCoverage.start(on_exit:) do
        root t.dir
        cover file
        coverage_dir t.dir
        ignore kind
      end
      covered = t.load(file)::M
      plain = source("PlainIg#{i}", body)
      eval(plain, TOPLEVEL_BINDING) # rubocop:disable Security/Eval
      same = inputs.map { covered.m(*_1) } ==
             inputs.map { call("PlainIg#{i}", _1) }
      manifest = PathCoverage::Manifest
      decisions = manifest.decisions(source('M', body), file, [kind])
      # a Condition's inspect shows its own and every nested one's
      shown = decisions.values.inspect
      named = shown.include?("operator=#{kind.inspect}")
      impossible = decisions.flat_map do |decision, condition|
        PathCoverage.recorder.decision_paths[decision].keys -
          PathCoverage::DecisionPaths.possible(condition)
      end
      ["#{kind} as #{position}", named, same, impossible]
    end
    expected = cases.map do |kind, position, _|
      ["#{kind} as #{position}", false, true, []]
    end
    assert_equal expected, actual
  end

  private

  # A module named name, its one method m's body body, on line 3.
  def source(name, body)
    "module #{name}\n  def self.m(a, b, c, ids, u)\n  " \
      "#{body}\n  end\nend\n"
  end

  # The result of the module named name's m called with args.
  def call(name, args)
    Object.const_get(name).m(*args)
  end
end
