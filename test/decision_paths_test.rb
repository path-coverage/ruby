require_relative 'test_helper'
require 'path_coverage/manifest'
require 'path_coverage/decision_paths'

class DecisionPathsTest < TidTest
  test 'Sp3x10', %w(
  | the possible paths through an && are every way its
  | leaves can be evaluated, true before false, a leaf an
  | && never reaches being nil
  ) do
    # ok?(id) && new?(id)
    decision = condition('&&', 16...23, 27...35)
    expected = [[true, true], [true, false], [false, nil]]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x20', %w(
  | an || stops at its first true leaf, so a leaf after one
  | that was true is nil
  ) do
    # ok?(id) || new?(id)
    decision = condition('||', 16...23, 27...35)
    expected = [[true, nil], [false, true], [false, false]]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x30', %w(
  | a ternary's path goes from its predicate into the arm
  | its predicate picks, through any condition that arm is,
  | the other arm's leaves being nil
  ) do
    # ok?(id) ? new?(id) && id.size == 6 : :no
    both = condition('&&', 26...34, 38...50)
    decision = condition(
      '?:', 16...23, arm(:then, 26...50, both), arm(:else, 53...56)
    )
    expected = [
      [true, true, true], [true, true, false],
      [true, false, nil], [false, nil, nil]
    ]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x40', %w(
  | a fixed leaf has its one outcome only, at any depth, so
  | a path needing its other outcome is impossible, not a gap
  ) do
    # opts[:v] || false ? :loud : :quiet
    either = condition('||', 16...24, 28...33)
    decision = condition(
      '?:', either, arm(:then, 36...41), arm(:else, 44...50),
      fixed: { 28...33 => :falsy }
    )
    expected = [[true, nil], [false, false]]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x50', %w(
  | a nested condition's own outcome decides whether the
  | chain around it goes on, as Ruby's short-circuit does
  ) do
    # ok?(id) && new?(id) || id.size == 6
    both = condition('&&', 16...23, 27...35)
    decision = condition('||', both, 39...51)
    expected = [
      [true, true, nil], [true, false, true], [true, false, false],
      [false, nil, true], [false, nil, false]
    ]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x60', %w(
  | Example: if order.big? && order.new?
  | The if's paths are its predicate's paths.
  | Its arms add no paths of their own.
  | It has no else arm, but still has a false path.
  ) do
    both = condition('&&', 20...30, 34...44)
    decision = condition('if', both, arm(:then, 49...50))
    expected = [[true, true], [true, false], [false, nil]]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x70', %w(
  | Example: unless order.big?
  | The unless's paths are its predicate's paths.
  | That is the same as for an if.
  ) do
    decision = condition('unless', 24...34, arm(:then, 39...40))
    expected = [[true], [false]]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x80', %w(
  | Example: case x when 1, 2 ... when String ... else ... end
  | The case tries its patterns in order: 1, 2, String.
  | The first pattern that matches ends the path.
  | The patterns after it are never tried, so they are nil.
  | When none match, the path is all false (the else).
  ) do
    small = condition('when', 28...29, 31...32)
    text = condition('when', 51...57)
    decision = condition(
      'case', arm(:when, 37...43, small), arm(:when, 62...67, text),
      arm(:else, 79...85)
    )
    expected = [
      [true, nil, nil], [false, true, nil],
      [false, false, true], [false, false, false]
    ]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x90', %w(
  | Example: ids.any? { |id| id.ok? }
  | any? can stop early, so its block's last answer decides it.
  | A path has two parts.
  | First, how many ids the block was called with:
  | 0 items, 1 item, or 2+ items.
  | Second, the block's last answer: true or false.
  | With 0 items the block was never called, so it is nil.
  ) do
    decision = condition('any?', 13...16, 29...35)
    expected = [
      ['0 items', nil], ['1 item', true], ['1 item', false],
      ['2+ items', true], ['2+ items', false]
    ]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x91', %w(
  | Example: ids.select { |id| id.ok? }
  | select calls its block with every item.
  | A path has two parts.
  | First, how many ids: 0 items, 1 item, or 2+ items.
  | Second, the block's answers: all true, all false, or both.
  | Both needs 2+ items.
  | With 0 items the block was never called, so it is nil.
  ) do
    decision = condition('select', 13...16, 31...37)
    expected = [
      ['0 items', nil],
      ['1 item', 'all true'], ['1 item', 'all false'],
      ['2+ items', 'all true'], ['2+ items', 'all false'],
      ['2+ items', 'both']
    ]
    assert_equal expected, PathCoverage::DecisionPaths.possible(decision)
  end

  test 'Sp3x92', %w(
  | Example: u.name&.size with name treated as present
  | name is never nil, so the &. never skips size.
  | The one possible path is name not nil.
  | Without the treatment, name nil is possible too.
  ) do
    source = "def k(u) = u.name&.size\n"
    manifest = PathCoverage::Manifest
    treated = manifest.decisions(source, 'k.rb', [], ['name']).values
    plain = manifest.decisions(source, 'k.rb').values
    actual = (treated + plain).map do |decision|
      PathCoverage::DecisionPaths.possible(decision)
    end
    assert_equal [[['not nil']], [['not nil'], ['nil']]], actual
  end

  test 'Sp3x93', %w(
  | Example: ids.select { |i| i.odd? }.any? && c with any?
  | treated as nonempty
  | any? is true exactly when select kept an item: with 1+
  | items, and an answer true.
  | So the paths with any? contradicting select are not
  | possible, eg 0 items with any? true.
  ) do
    source = "def k(ids, c) = ids.select { |i| i.odd? }.any? && c\n"
    manifest = PathCoverage::Manifest
    decisions = manifest.decisions(source, 'k.rb', [], [], ['any?'])
    expected = [
      ['0 items', nil, false, nil],
      ['1 item', 'all true', true, true],
      ['1 item', 'all true', true, false],
      ['1 item', 'all false', false, nil],
      ['2+ items', 'all true', true, true],
      ['2+ items', 'all true', true, false],
      ['2+ items', 'all false', false, nil],
      ['2+ items', 'both', true, true],
      ['2+ items', 'both', true, false]
    ]
    actual = PathCoverage::DecisionPaths.possible(decisions.values.first)
    assert_equal expected, actual
  end

  test 'Sp3x94', %w(
  | Example: (cached || fetched).any? && c with any? treated as
  | nonempty
  | An || cannot tell whether its value has items.
  | So any? stays true or false on each of its paths.
  ) do
    source = 'def k(cached, fetched, c) = ' \
             "(cached || fetched).any? && c\n"
    manifest = PathCoverage::Manifest
    decisions = manifest.decisions(source, 'k.rb', [], [], ['any?'])
    treated = PathCoverage::DecisionPaths.possible(decisions.values.first)
    plain = manifest.decisions(source, 'k.rb').values.first
    assert_equal PathCoverage::DecisionPaths.possible(plain), treated
    assert_equal 9, treated.size
  end

  test 'Sp3x98', %w(
  | Example: [ids.select { |i| i.odd? }].any? && c, and the same
  | with two selects in the array, with any? treated as nonempty
  | The array, not a select, is any?'s receiver, and it has
  | items whatever the selects keep.
  | So any? stays true or false on each path, as untreated.
  ) do
    sources = [
      "def k(ids, c) = [ids.select { |i| i.odd? }].any? && c\n",
      'def k(ids, c) = [ids.select { |i| i.odd? }, ' \
      "ids.select { |i| i.even? }].any? && c\n"
    ]
    manifest = PathCoverage::Manifest
    same = sources.map do |source|
      decisions = manifest.decisions(source, 'k.rb', [], [], ['any?'])
      plain = manifest.decisions(source, 'k.rb')
      [decisions, plain].map do |all|
        PathCoverage::DecisionPaths.possible(all.values.last)
      end.uniq.size
    end
    assert_equal [1, 1], same
  end

  test 'Sp3x99', %w(
  | Example: ids.any? { |i| i.odd? } && c
  | The any? is a decision of its own, the &&'s first leaf its
  | value, true or false, so c is evaluated only where that
  | leaf is true. Which of the any?'s paths give true is its
  | card tree's gives.
  ) do
    source = "def k(ids, c) = ids.any? { |i| i.odd? } && c\n"
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal %w(k.rb:1:16 k.rb:1:20), decisions.keys
    actual = PathCoverage::DecisionPaths.possible(decisions['k.rb:1:16'])
    assert_equal [[true, true], [true, false], [false, nil]], actual
  end

  test 'Sp3x9a', %w(
  | Example: ids.select { |i| i.odd? }.any? { |i| i > 1 } && c
  | The leaf is wholly the any?, a decision of its own, as is the
  | select, its receiver: so three decisions, the &&'s first leaf
  | the any?'s value, and c evaluated only where it is true.
  ) do
    source = 'def k(ids, c) = ' \
             "ids.select { |i| i.odd? }.any? { |i| i > 1 } && c\n"
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal %w(k.rb:1:16 k.rb:1:42 k.rb:1:20), decisions.keys
    actual = PathCoverage::DecisionPaths.possible(decisions['k.rb:1:16'])
    assert_equal [[true, true], [true, false], [false, nil]], actual
  end

  test 'Sp3x95', %w(
  | Example: ids.reject { |i| i.odd? }.any?, and each other
  | block method whose result can have items, over real ids
  | Whether its result has items, as items? says from the
  | path the call took, is what Ruby's any? says, or nil when
  | the path cannot tell.
  | It is never wrong.
  ) do
    idss = [[], [1], [2], [1, 3], [2, 4], [1, 2], [2, 1]]
    all = [false, true, false, true, false, true, true]
    told = {
      'select' => all, 'filter' => all, 'filter_map' => all,
      'reject' => [false, false, true, false, true, true, true],
      'partition' => [true] * 7,
      'take_while' => [false, true, false, true, false, nil, false]
    }
    actual = told.keys.to_h do |name|
      said = idss.map { |ids| told_and_real(name, ids) }
      filled = said.map { |says, real| says.nil? ? real : says }
      [name, [said.map(&:first), filled == said.map(&:last)]]
    end
    expected = told.transform_values { |says| [says, true] }
    assert_equal expected, actual
  end

  test 'Sp3x96', %w(
  | Example: xs.find { |x| x > 1 } || 0
  | find is nil when it was called with no items, or its last
  | answer was false, as then nothing was found.
  | So find truthy on those paths is not possible.
  | With its last answer true it found an item, which may
  | itself be nil, so it can still be true or false.
  ) do
    source = "def k(xs) = xs.find { |x| x > 1 } || 0\n"
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    expected = [
      ['0 items', nil, false, true],
      ['1 item', true, true, nil],
      ['1 item', true, false, true],
      ['1 item', false, false, true],
      ['2+ items', true, true, nil],
      ['2+ items', true, false, true],
      ['2+ items', false, false, true]
    ]
    actual = PathCoverage::DecisionPaths.possible(decisions.values.first)
    assert_equal expected, actual
  end

  test 'Sp3x97', %w(
  | Example: xs.select { |x| x > 1 } || []
  | select always returns an array, which is truthy, however
  | many items it was called with and whatever they answered.
  | It is a decision of its own, and its every path gives the ||'s
  | leaf true: so that leaf is never false, and the [] never
  | runs.
  ) do
    source = "def k(xs) = xs.select { |x| x > 1 } || []\n"
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal %w(k.rb:1:12 k.rb:1:15), decisions.keys
    actual = PathCoverage::DecisionPaths.possible(decisions['k.rb:1:12'])
    assert_equal [[true, nil]], actual
  end

  private

  # [whether items? says the result of ids.name { |i| i.odd? }
  # has items, from the path the call took, Ruby's any? of it].
  def told_and_real(name, ids)
    answers = []
    result = ids.public_send(name) do |i|
      i.odd?.tap { |answer| answers << answer }
    end
    decision = condition(name, 0...3, 10...16)
    outcomes = {
      0...3 => items(answers), 10...16 => answer(name, answers)
    }
    [PathCoverage::Kinds::Block.items?(decision, outcomes),
     result.any?]
  end

  # The receiver's leaf outcome of a block method whose block
  # gave answers.
  def items(answers)
    PathCoverage::ITEMS[[answers.size, 2].min]
  end

  # The block's leaf outcome: its last answer for a method that
  # stops early, else its answers over every item.
  def answer(name, answers)
    return nil if answers.empty?
    return answers.last if PathCoverage::STOP_EARLY.include?(name)
    return PathCoverage::ANSWERS[2] if answers.uniq.size == 2

    PathCoverage::ANSWERS[answers.first ? 0 : 1]
  end
end
