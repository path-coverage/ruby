require_relative 'test_helper'
require 'path_coverage/manifest'
require 'path_coverage/decision_paths'
require 'path_coverage/decision_tree'

class DecisionTreeTest < TidTest
  test 'EuNs10', %w(
  | Example: ok?(id) && id.start_with?('N')
  | The tree names its operator (&&).
  | It has one column per path, with that path's count.
  | Paths never taken (count 0) come first.
  | Each leaf has its source text, eg ok?(id).
  | The text is cut from the manifest's byte range.
  | Each leaf has its outcome on each path.
  | A leaf a path never reached is nil.
  | The decision has its value on each path too.
  ) do
    source = <<~RUBY
      module Kata
        def self.ok?(id) = !id.empty?
        def self.kata?(id) = ok?(id) && id.start_with?('N')
      end
    RUBY
    decision = condition('&&', 67...74, 78...97)
    paths = [
      { path: [true, true], count: 1 },
      { path: [true, false], count: 0 },
      { path: [false, nil], count: 1 }
    ]
    expected = {
      operator: '&&', counts: [0, 1, 1],
      cells: [false, true, false],
      operands: [
        { text: 'ok?(id)', cells: [true, true, false] },
        { text: "id.start_with?('N')", cells: [false, true, nil] }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs30', %w(
  | Example: ok?(id) && (new?(id) || id.size == 6)
  | The nested || is a subtree under the &&.
  | Its leaves take their outcomes left to right.
  | Its value on a path is that of the last leaf reached.
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && (new?(id) || id.size == 6)
      end
    RUBY
    either = condition('||', 28...36, 40...52)
    decision = condition('&&', 16...23, either)
    paths = [
      { path: [true, true, nil], count: 2 },
      { path: [true, false, true], count: 0 },
      { path: [true, false, false], count: 1 },
      { path: [false, nil, nil], count: 1 }
    ]
    expected = {
      operator: '&&', counts: [0, 2, 1, 1],
      cells: [true, true, false, false],
      operands: [
        { text: 'ok?(id)', cells: [true, true, true, false] },
        {
          operator: '||', cells: [true, true, false, nil],
          operands: [
            { text: 'new?(id)', cells: [false, true, false, nil] },
            { text: 'id.size == 6', cells: [true, nil, false, nil] }
          ]
        }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs70', %w(
  | Example: ok?(id) ? new?(id) && id.size == 6 : :no
  | The predicate ok?(id) decides which arm each path took.
  | Each arm has its text, eg :no.
  | Each arm has whether each path took it.
  | The then arm holds a condition, so it has its tree.
  | The else arm (:no) is plain, so its tree is nil.
  | The ternary's value on a path is its taken arm's value.
  | A plain arm's value is nil.
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) ? new?(id) && id.size == 6 : :no
      end
    RUBY
    both = condition('&&', 26...34, 38...50)
    decision = condition(
      '?:', 16...23, arm(:then, 26...50, both), arm(:else, 53...56)
    )
    paths = [
      { path: [true, true, true], count: 1 },
      { path: [true, true, false], count: 0 },
      { path: [true, false, nil], count: 2 },
      { path: [false, nil, nil], count: 3 }
    ]
    expected = {
      operator: '?:', counts: [0, 1, 2, 3],
      cells: [false, true, false, nil],
      operands: [
        { text: 'ok?(id)', cells: [true, true, true, false] },
        {
          arm: :then, text: 'new?(id) && id.size == 6',
          cells: [true, true, true, false],
          body: {
            operator: '&&', cells: [false, true, false, nil],
            operands: [
              { text: 'new?(id)', cells: [true, true, false, nil] },
              { text: 'id.size == 6', cells: [false, true, nil, nil] }
            ]
          }
        },
        {
          arm: :else, text: ':no',
          cells: [false, false, false, true], body: nil
        }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs80', %w(
  | Example: if order.big? && order.new? 5 else 7 end
  | An if's tree is the same as a ternary's.
  | Its predicate, an && here, is one leaf, the && a decision of
  | its own; the predicate decides which arm each path took.
  | Both arms (5 and 7) are plain, so the if's value is nil.
  ) do
    source = <<~RUBY
      def fee(order)
        if order.big? && order.new?
          5
        else
          7
        end
      end
    RUBY
    decision = PathCoverage::Manifest.decisions(source,
                                                'k.rb').values.first
    paths = [
      { path: [true], count: 1 },
      { path: [false], count: 2 }
    ]
    expected = {
      operator: 'if', counts: [1, 2],
      cells: [nil, nil],
      operands: [
        { text: 'order.big? && order.new?', cells: [true, false] },
        { arm: :then, text: '5', cells: [true, false], body: nil },
        { arm: :else, text: '7', cells: [false, true], body: nil }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs81', %w(
  | Example: if x end
  | The then arm has no statements.
  | So its text is nil.
  ) do
    source = <<~RUBY
      def k(x)
        if x
        end
      end
    RUBY
    decision = PathCoverage::Manifest.decisions(source,
                                                'k.rb').values.first
    paths = [
      { path: [true], count: 1 },
      { path: [false], count: 0 }
    ]
    expected = {
      operator: 'if', counts: [0, 1], cells: [nil, nil],
      operands: [
        { text: 'x', cells: [false, true] },
        { arm: :then, text: nil, cells: [false, true], body: nil }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs82', %w(
  | Example: unless order.big? 5 else 7 end
  | The then arm (5) is taken when order.big? is false.
  | The else arm (7) is taken when order.big? is true.
  ) do
    source = <<~RUBY
      def fee(order)
        unless order.big?
          5
        else
          7
        end
      end
    RUBY
    decision = condition(
      'unless', 24...34, arm(:then, 39...40), arm(:else, 52...53)
    )
    paths = [
      { path: [true], count: 1 },
      { path: [false], count: 0 }
    ]
    expected = {
      operator: 'unless', counts: [0, 1], cells: [nil, nil],
      operands: [
        { text: 'order.big?', cells: [false, true] },
        { arm: :then, text: '5', cells: [true, false], body: nil },
        { arm: :else, text: '7', cells: [false, true], body: nil }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs83', %w(
  | Example: case x when 1, 2 ... when String ... else ... end
  | The tree has a row for each when.
  | The row holds that when's patterns, eg 1 and 2.
  | A when is taken on a path where one of its patterns
  | matched.
  | The tree has a row for the else too.
  | The else is taken on a path where no pattern matched.
  ) do
    source = <<~RUBY
      def kind(x)
        case x
        when 1, 2
          :small
        when String
          :text
        else
          :other
        end
      end
    RUBY
    small = condition('when', 28...29, 31...32)
    text = condition('when', 51...57)
    decision = condition(
      'case', arm(:when, 37...43, small), arm(:when, 62...67, text),
      arm(:else, 79...85)
    )
    paths = [
      { path: [true, nil, nil], count: 1 },
      { path: [false, true, nil], count: 0 },
      { path: [false, false, true], count: 2 },
      { path: [false, false, false], count: 0 }
    ]
    expected = {
      operator: 'case', counts: [0, 0, 1, 2],
      cells: [nil, nil, nil, nil],
      operands: [
        {
          arm: :when, text: ':small',
          cells: [true, false, true, false],
          body: {
            operator: 'when', cells: [true, false, true, false],
            operands: [
              { text: '1', cells: [false, false, true, false] },
              { text: '2', cells: [true, false, nil, false] }
            ]
          }
        },
        {
          arm: :when, text: ':text',
          cells: [false, false, false, true],
          body: {
            operator: 'when', cells: [nil, false, nil, true],
            operands: [
              { text: 'String', cells: [nil, false, nil, true] }
            ]
          }
        },
        {
          arm: :else, text: ':other',
          cells: [false, true, false, false], body: nil
        }
      ]
    }
    actual = PathCoverage::DecisionTree.of(source, decision, paths)
    assert_equal expected, actual
  end

  test 'EuNs84', %w(
  | Example: (a || b).any? && c
  | The || sits inside the leaf (a || b).any?.
  | The leaf's text before the || heads the ||'s row: ( ||.
  | The leaf's text after the || is the leaf's own row: ).any?.
  | So the rows read as the code does.
  ) do
    source = "def k(a, b, c) = (a || b).any? && c\n"
    found = PathCoverage::Manifest.decisions(source, 'k.rb')
    decision = found.values.first
    possible = PathCoverage::DecisionPaths.possible(decision)
    paths = possible.map { |path| { path:, count: 0 } }
    tree = PathCoverage::DecisionTree.of(source, decision, paths)
    inner, leaf = tree[:operands].first[:operands]
    assert_equal ['( ||', ').any?'], [inner[:label], leaf[:text]]
  end

  test 'EuNs85', %w(
  | Example: user&.account&.owner as a decision of its own
  | Its leaves are its receivers, user and account, as only
  | they decide its path, and its tree shows just those: owner
  | decides no path, and is called exactly where account is not
  | nil.
  ) do
    source = "def owner_of(user) = user&.account&.owner\n"
    found = PathCoverage::Manifest.decisions(source, 'k.rb')
    decision = found.values.first
    possible = PathCoverage::DecisionPaths.possible(decision)
    paths = possible.map { |path| { path:, count: 0 } }
    tree = PathCoverage::DecisionTree.of(source, decision, paths)
    texts = tree[:operands].map { _1[:text] }
    assert_equal %w(user account), texts
  end

  test 'EuNs86', %w(
  | Example: if member ... elsif big ... end
  | The elsif is an if decision of its own, its tree labelled
  | elsif, as it is written, though its operator is if.
  | The first if's tree has no label, its operator if
  | naming it.
  ) do
    source = <<~RUBY
      def fee(member, big)
        if member
          5
        elsif big
          10
        end
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    trees = decisions.transform_values do |decision|
      possible = PathCoverage::DecisionPaths.possible(decision)
      paths = possible.map { |path| { path:, count: 0 } }
      PathCoverage::DecisionTree.of(source, decision, paths)
    end
    labels = trees.transform_values { [_1[:operator], _1[:label]] }
    expected = {
      'k.rb:2:2' => ['if', nil], 'k.rb:4:2' => %w(if elsif)
    }
    assert_equal expected, labels
  end

  test 'EuNs87', %w(
  | Example: case x when 1 then :one else :other end, each path
  | taken once
  | Its else is taken on each path its one when did not match,
  | and not on the one it did.
  ) do
    source = <<~RUBY
      def kind(x)
        case x
        when 1 then :one
        else :other
        end
      end
    RUBY
    found = PathCoverage::Manifest.decisions(source, 'k.rb')
    decision = found.values.first
    possible = PathCoverage::DecisionPaths.possible(decision)
    paths = possible.map { |path| { path:, count: 1 } }
    tree = PathCoverage::DecisionTree.of(source, decision, paths)
    arms = tree[:operands].map { [_1[:arm], _1[:cells]] }
    expected = [[:when, [true, false]], [:else, [false, true]]]
    assert_equal expected, arms
  end
end
