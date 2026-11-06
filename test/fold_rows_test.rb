require_relative 'test_helper'
require 'path_coverage/fold_rows'

class FoldRowsTest < TidTest
  test 'gae530', %w(
  | Example: the tree of ok?(id) && id.start_with?('N')
  | It has one row per operand: its text, then its outcome on
  | each path, T or F, blank where the path never reached it.
  ) do
    decisions = [
      {
        operator: '&&', counts: [1, 1, 1],
        cells: [true, false, false],
        operands: [
          { text: 'ok?(id)', cells: [true, true, false] },
          { text: "id.start_with?('N')", cells: [true, false, nil] }
        ]
      }
    ]
    actual = of_kind(rows_of(decisions), 'operand').map { shown(_1) }
    expected = [
      ['ok?(id)', 'T', 'T', 'F'],
      ["id.start_with?('N')", 'T', 'F', '']
    ]
    assert_equal expected, actual
  end

  test 'gae535', %w(
  | a tree opens, for each decision, with a row naming its
  | operator and each path's count, how many times it was
  | taken; its operands branch below
  ) do
    decisions = [
      {
        operator: '&&', counts: [0, 1284, 1],
        cells: [false, true, false],
        operands: [
          { text: 'ok?(id)', cells: [true, true, false] },
          { text: 'new?(id)', cells: [false, true, nil] }
        ]
      }
    ]
    rows = rows_of(decisions)
    decision = rows.first
    assert_equal ['decision', '&&', [0, 1284, 1]],
                 [decision[:kind], decision[:label][:text],
                  decision[:counts]]
    assert_equal %w(ths lhs), branches(rows)
  end

  test 'gae538', %w(
  | a nested condition's operator branches from its parent
  | like an operand, and its own operands branch below it,
  | indented under its branch so the tree reads as one
  ) do
    either = {
      operator: '||', cells: [true, false],
      operands: [
        { text: 'new?(id)', cells: [true, false] },
        { text: 'id.size == 6', cells: [nil, false] }
      ]
    }
    decisions = [
      {
        operator: '&&', counts: [2, 1], cells: [true, false],
        operands: [{ text: 'ok?(id)', cells: [true, true] }, either]
      }
    ]
    rows = rows_of(decisions)
    named = rows - of_kind(rows, 'operand')
    assert_equal(['&&', '||'], named.map { _1[:label][:text] })
    assert_equal %w(ths lhs sssths ssslhs), branches(rows)
    texts = of_kind(rows, 'operand').map { _1[:label][:text] }
    assert_equal ['ok?(id)', 'new?(id)', 'id.size == 6'], texts
  end

  test 'gae539', %w(
  | a nested condition that is not the last operand keeps its
  | parent's branch line running down beside its own operands
  ) do
    either = {
      operator: '||', cells: [true, true],
      operands: [
        { text: 'ok?(id)', cells: [true, false] },
        { text: 'new?(id)', cells: [nil, true] }
      ]
    }
    decisions = [
      {
        operator: '&&', counts: [1, 1], cells: [true, true],
        operands: [
          either, { text: 'id.size == 6', cells: [true, true] }
        ]
      }
    ]
    assert_equal %w(ths vssths vsslhs lhs),
                 branches(rows_of(decisions))
  end

  test 'gae531', %w(
  | a ternary's arm has a row of its own, ? or : before it: an
  | arm holding a condition is named by its operator, shows
  | its value on each path, and has the condition's operands
  | branching below; a plain arm is named by its text, and
  | marks each path that took it
  ) do
    both = {
      operator: '&&', cells: [false, true, nil],
      operands: [
        { text: 'new?(id)', cells: [true, true, nil] },
        { text: 'id.size == 6', cells: [false, true, nil] }
      ]
    }
    decisions = [
      {
        operator: '?:', counts: [0, 1, 2], cells: [false, true, nil],
        operands: [
          { text: 'ok?(id)', cells: [true, true, false] },
          { arm: :then, text: 'new?(id) && id.size == 6',
            cells: [true, true, false], body: both },
          { arm: :else, text: ':no', cells: [false, false, true],
            body: nil }
        ]
      }
    ]
    rows = rows_of(decisions)
    actual = of_kind(rows, 'arm').map { shown(_1) }
    expected = [['? &&', 'F', 'T', ''], [': :no', '', '', 'taken']]
    assert_equal expected, actual
    assert_equal %w(ths ths vssths vsslhs lhs), branches(rows)
  end

  test 'gae533', %w(
  | Example: if x == a && y == b alpha else beta end
  | An if's fold shows its predicate's leaves, but no row for
  | its arms: which arm a path takes follows from those leaves,
  | and the code in an arm is a card row of its own.
  ) do
    both = {
      operator: '&&', cells: [false, true, false],
      operands: [
        { text: 'x == a', cells: [true, true, false] },
        { text: 'y == b', cells: [false, true, nil] }
      ]
    }
    decisions = [
      {
        operator: 'if', counts: [0, 1, 2], cells: [nil, nil, nil],
        operands: [
          both,
          { arm: :then, text: 'alpha', cells: [false, true, false],
            body: nil },
          { arm: :else, text: 'beta', cells: [true, false, true],
            body: nil }
        ]
      }
    ]
    rows = rows_of(decisions)
    assert_equal [], of_kind(rows, 'arm')
    texts = of_kind(rows, 'operand').map { _1[:label][:text] }
    assert_equal ['x == a', 'y == b'], texts
  end

  test 'gae547', %w(
  | Example: unless x alpha end
  | Its fold has no row for its arm, as for an if.
  ) do
    decisions = [
      {
        operator: 'unless', counts: [0, 1], cells: [nil, nil],
        operands: [
          { text: 'x', cells: [false, true] },
          { arm: :then, text: 'alpha', cells: [true, false],
            body: nil }
        ]
      }
    ]
    assert_equal [], of_kind(rows_of(decisions), 'arm')
  end

  test 'gae580', %w(
  | Example: if order[:gift] && its next line (order[:wrap])
  | A leaf written over two lines reads as one in its fold, its
  | line break and indent one space, so its row stays one line.
  ) do
    decisions = [
      {
        operator: 'if', counts: [1, 1], cells: [nil, nil],
        operands: [
          { text: "order[:gift] &&\n     (order[:wrap])",
            cells: [true, false] }
        ]
      }
    ]
    operands = of_kind(rows_of(decisions), 'operand')
    texts = operands.map { _1[:label][:text] }
    assert_equal ['order[:gift] && (order[:wrap])'], texts
  end

  test 'gae579', %w(
  | Example: return total if order[:pickup], its predicate false
  | on one path and true on the other
  | Its arm returns, so its fold has a row for it, return,
  | marking each path that leaves the method there, the true
  | one, blank on the other.
  ) do
    decisions = [
      {
        operator: 'if', counts: [1, 1], cells: [nil, nil],
        operands: [
          { text: 'order[:pickup]', cells: [false, true] },
          { arm: :then, text: 'return total', cells: [false, true],
            body: nil }
        ]
      }
    ]
    actual = of_kind(rows_of(decisions), 'leaves').map { shown(_1) }
    assert_equal [['return', '', 'leaves']], actual
  end

  test 'gae581', %w(
  | Example: return total if order[:pickup], on line 50
  | Its fold's return row is placed at its arm's code, return
  | total, so hovering return in the code pane opens the fold
  | and lights that row.
  ) do
    decisions = [
      {
        operator: 'if', counts: [1, 1], cells: [nil, nil],
        at: [50, 17, 50, 34],
        operands: [
          { text: 'order[:pickup]', cells: [false, true],
            at: [50, 20, 50, 34] },
          { arm: :then, text: 'return total', at: [50, 4, 50, 16],
            cells: [false, true], body: nil }
        ]
      }
    ]
    placed = of_kind(rows_of(decisions), 'leaves').map { _1[:at] }
    assert_equal [[50, 4, 50, 16]], placed
  end

  test 'gae566', %w(
  | Example: x ? :a : :b
  | A ?:'s fold keeps a row for each arm, ? and :, as its arms
  | are part of its one expression, each marking the paths that
  | took it.
  ) do
    decisions = [
      {
        operator: '?:', counts: [0, 1], cells: [nil, nil],
        operands: [
          { text: 'x', cells: [true, false] },
          { arm: :then, text: ':a', cells: [true, false], body: nil },
          { arm: :else, text: ':b', cells: [false, true], body: nil }
        ]
      }
    ]
    actual = of_kind(rows_of(decisions), 'arm').map { shown(_1) }
    expected = [['? :a', 'taken', ''], [': :b', '', 'taken']]
    assert_equal expected, actual
  end

  test 'gae567', %w(
  | Example: the tree of ok?(id) && id.size == 6
  | Its operator && is coloured as it is in the code.
  | So is each operand, eg the 6 of id.size == 6.
  ) do
    decisions = [
      {
        operator: '&&', counts: [0, 1], cells: [true, false],
        operands: [
          { text: 'ok?(id)', cells: [true, false] },
          { text: 'id.size == 6', cells: [true, nil] }
        ]
      }
    ]
    coloured = rows_of(decisions).flat_map do |row|
      text, tokens = row[:label].values_at(:text, :tokens)
      tokens.map { |from, to, css| [css, text[from...to]] }
    end
    assert_equal [%w(o &&), %w(n 6)], coloured
  end

  test 'gae548', %w(
  | Example: case x when 1 then :small else :other end
  | Its fold has no row for its arms, as for an if; but each
  | when's patterns are leaves of the case, so the when shows,
  | whether it matched on each path, T F, its pattern 1 below.
  ) do
    small = {
      operator: 'when', cells: [true, false],
      operands: [{ text: '1', cells: [true, false] }]
    }
    decisions = [
      {
        operator: 'case', counts: [0, 1], cells: [nil, nil],
        operands: [
          { arm: :when, text: ':small', cells: [true, false],
            body: small },
          { arm: :else, text: ':other', cells: [false, true],
            body: nil }
        ]
      }
    ]
    rows = rows_of(decisions)
    assert_equal [], of_kind(rows, 'arm')
    matched = of_kind(rows, 'subtree').map { shown(_1) }
    assert_equal [%w(when T F)], matched
    texts = of_kind(rows, 'operand').map { _1[:label][:text] }
    assert_equal ['1'], texts
  end

  test 'gae549', %w(
  | Example: ids.any? { |id| id.ok? }
  | The ids row shows how many items the block was called
  | with on each path: 0, 1, or * for two or more.
  | The id.ok? row shows its last answer: T or F.
  | It is blank where the block was never called.
  ) do
    decisions = [
      {
        operator: 'any?', counts: [0, 1, 2],
        cells: [nil, true, false],
        operands: [
          { text: 'ids', cells: ['0 items', '1 item', '2+ items'] },
          { text: 'id.ok?', cells: [nil, true, false] }
        ]
      }
    ]
    operands = of_kind(rows_of(decisions), 'operand')
    actual = operands.map { shown(_1).drop(1) }
    assert_equal [%w(0 1 *), ['', 'T', 'F']], actual
  end

  test 'gae54a', %w(
  | Example: ids.select { |id| id.ok? }
  | select calls its block with every item.
  | The id.ok? row shows its answers on each path.
  | T when all were true.
  | F when all were false.
  | TF when both.
  ) do
    decisions = [
      {
        operator: 'select', counts: [0, 1, 2], cells: [nil, nil, nil],
        operands: [
          { text: 'ids', cells: ['1 item', '2+ items', '2+ items'] },
          { text: 'id.ok?', cells: ['all true', 'all false', 'both'] }
        ]
      }
    ]
    last = of_kind(rows_of(decisions), 'operand').last
    assert_equal %w(T F TF), shown(last).drop(1)
  end

  private

  # The rows of each of decisions' folds, as FoldRows.rows gives them,
  # one after another.
  def rows_of(decisions)
    decisions.flat_map { PathCoverage::FoldRows.rows(_1) }
  end

  # The rows of rows of kind, eg operand; none when none are.
  def of_kind(rows, kind)
    rows.group_by { _1[:kind] }.fetch(kind, [])
  end

  # Example: a tee then a dash then a space gives ths.
  # Each row's branch, but a decision row's, which has none.
  def branches(rows)
    rows.map { _1[:branch] }.reject(&:empty?)
  end

  # Example: an arm's row gives ['? :a', 'taken', ''].
  # What a row shows: its label's text, then each cell's mark,
  # eg taken, or else its text.
  def shown(row)
    cells = row[:cells].map do |text, mark|
      [mark, text].compact.first
    end
    [row[:label][:text], *cells]
  end
end
