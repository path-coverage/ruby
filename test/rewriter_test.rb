require_relative 'test_helper'
require 'path_coverage/rewriter'

class RewriterTest < TidTest
  test '6D1Ka2', %w(
  | each operand of an && is wrapped in a record call
  | keyed by the && decision's path:line:column
  | and the operand's index, at the byte ranges
  | the manifest found, with no parse of its own; the
  | whole && is wrapped in a leave call, outside them, whose
  | first argument enters the decision, so each evaluation's
  | path through it is counted
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id)
      end
    RUBY
    both = condition('&&', 16...23, 27...35, extent: 16...35)
    decisions = { 'k.rb:2:2' => both }
    expected = [
      'def kata?(id)',
      '  PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 2), ' \
      'PathCoverage.record("k.rb:2:2", 0, ok?(id)) && ' \
      'PathCoverage.record("k.rb:2:2", 1, new?(id)))',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ka8', %w(
  | the leaves of a nested condition are wrapped too,
  | indexed left to right across the whole decision,
  | and the parentheses grouping them are kept
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && (new?(id) || id.size == 6)
      end
    RUBY
    either = condition('||', 28...36, 40...52, extent: 28...52)
    both = condition('&&', 16...23, either, extent: 16...53)
    decisions = { 'k.rb:2:2' => both }
    expected = [
      'def kata?(id)',
      '  PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 3), ' \
      'PathCoverage.record("k.rb:2:2", 0, ok?(id)) && ' \
      '(PathCoverage.record("k.rb:2:2", 1, new?(id)) || ' \
      'PathCoverage.record("k.rb:2:2", 2, id.size == 6)))',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ka9', %w(
  | a command-call leaf is also wrapped in parentheses of its
  | own, since id.include? 'N' is no bare argument; other
  | leaves are not, as parentheses would give a continuation
  | line a line-coverage count of its own; a whole and or or
  | is no bare argument either, so its leave call holds it
  | in parentheses
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) and id.include? 'N'
      end
    RUBY
    decision = condition(
      'and', 16...23, 28...43, commands: [28...43], extent: 16...43
    )
    decisions = { 'k.rb:2:2' => decision }
    expected = [
      'def kata?(id)',
      '  PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 2), (' \
      'PathCoverage.record("k.rb:2:2", 0, ok?(id)) and ' \
      "PathCoverage.record(\"k.rb:2:2\", 1, (id.include? 'N'))" \
      '))',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Kb4', %w(
  | a file with no && decisions is returned unchanged
  ) do
    source = <<~RUBY
      def kata?(id)
        return :ok if ok?(id)
      end
    RUBY
    rewriter = PathCoverage::Rewriter
    assert_equal source, rewriter.rewrite(source, {})
  end

  test '6D1Ke1', %w(
  | Example: if order.big? return 5 end
  | The leave call wraps the predicate (order.big?) only.
  | The if's path is decided once the predicate is known.
  | So the return 5 cannot skip the leave call.
  | The path is still counted.
  ) do
    source = <<~RUBY
      def fee(order)
        if order.big?
          return 5
        end
        7
      end
    RUBY
    choice = condition(
      'if', 20...30, arm(:then, 35...43), extent: 17...30
    )
    decisions = { 'k.rb:2:2' => choice }
    expected = [
      'def fee(order)',
      '  if PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 1), ' \
      'PathCoverage.record("k.rb:2:2", 0, order.big?))',
      '    return 5',
      '  end',
      '  7',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ke4', %w(
  | Example: unless order.big? return 5 end
  | The leave call wraps the predicate (order.big?) only.
  | That is the same as for an if.
  ) do
    source = <<~RUBY
      def fee(order)
        unless order.big?
          return 5
        end
        7
      end
    RUBY
    choice = condition(
      'unless', 24...34, arm(:then, 39...47), extent: 17...34
    )
    decisions = { 'k.rb:2:2' => choice }
    expected = [
      'def fee(order)',
      '  unless PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 1), ' \
      'PathCoverage.record("k.rb:2:2", 0, order.big?))',
      '    return 5',
      '  end',
      '  7',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ke5', %w(
  | Example: case x when 1, 2 ... else ... end
  | Each pattern (1 and 2) is wrapped in a when_match call.
  | The when_match call is a stand-in for its pattern.
  | The stand-ins enter and leave the decision themselves.
  | So nothing wraps the case, or its subject x.
  ) do
    source = <<~RUBY
      def kind(x)
        case x
        when 1, 2
          :small
        else
          :other
        end
      end
    RUBY
    small = condition('when', 28...29, 31...32, extent: 28...32)
    choice = condition(
      'case', arm(:when, 37...43, small), arm(:else, 55...61),
      extent: 14...20
    )
    decisions = { 'k.rb:2:2' => choice }
    expected = [
      'def kind(x)',
      '  case x',
      '  when PathCoverage.when_match("k.rb:2:2", 0, 2, 1), ' \
      'PathCoverage.when_match("k.rb:2:2", 1, 2, 2)',
      '    :small',
      '  else',
      '    :other',
      '  end',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ke6', %w(
  | Example: ids.any? { |id| id.ok? }
  | The whole call is wrapped in a leave call that enters it.
  | Inside that, an end_items call around a begin_items call.
  | They note the receiver as leaf 0.
  | The block's expression (id.ok?) is wrapped in an item_at call.
  | So each of the block's answers is noted, as leaf 1.
  | Nothing else is evaluated, eg ids.size.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.any? { |id| id.ok? }
      end
    RUBY
    found = condition('any?', 13...16, 29...35, extent: 13...37)
    decisions = { 'k.rb:2:6' => found }
    expected = [
      'def k(ids)',
      '  PathCoverage.leave(PathCoverage.enter("k.rb:2:6", 2), ' \
      'PathCoverage.end_items("k.rb:2:6", 0, ' \
      'PathCoverage.begin_items("k.rb:2:6", 0), ' \
      'ids.any? { |id| ' \
      'PathCoverage.item_at("k.rb:2:6", 0, id.ok?) }))',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ke7', %w(
  | Example: ids.select { |id| id.ok? }
  | select calls its block with every item.
  | So the block's expression is wrapped in an answer_at call.
  | An answer_at call notes every answer, not only the last.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.select { |id| id.ok? }
      end
    RUBY
    kept = condition('select', 13...16, 31...37, extent: 13...39)
    decisions = { 'k.rb:2:6' => kept }
    expected = [
      'def k(ids)',
      '  PathCoverage.leave(PathCoverage.enter("k.rb:2:6", 2), ' \
      'PathCoverage.end_items("k.rb:2:6", 0, ' \
      'PathCoverage.begin_items("k.rb:2:6", 0), ' \
      'ids.select { |id| ' \
      'PathCoverage.answer_at("k.rb:2:6", 0, id.ok?) }))',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Ke2', %w(
  | Example: if a and b
  | The predicate (a and b) cannot be a bare argument.
  | So it is put in parentheses inside the leave call.
  ) do
    source = <<~RUBY
      def k(a, b)
        if a and b
          1
        end
      end
    RUBY
    both = condition('and', 17...18, 23...24, extent: 17...24)
    choice = condition(
      'if', both, arm(:then, 29...30), extent: 14...24
    )
    decisions = { 'k.rb:2:2' => choice }
    expected = [
      'def k(a, b)',
      '  if PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 2), ' \
      '(PathCoverage.record("k.rb:2:2", 0, a) and ' \
      'PathCoverage.record("k.rb:2:2", 1, b)))',
      '    1',
      '  end',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Kd1', %w(
  | a ternary is wrapped whole, its arms included, in a leave
  | call, so each evaluation's path runs on into the arm its
  | predicate picks
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) ? :ok : :no
      end
    RUBY
    arms = [arm(:then, 26...29), arm(:else, 32...35)]
    decisions = {
      'k.rb:2:2' => condition('?:', 16...23, *arms, extent: 16...35)
    }
    expected = [
      'def kata?(id)',
      '  PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 1), ' \
      'PathCoverage.record("k.rb:2:2", 0, ok?(id)) ? :ok : :no)',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Kd3', %w(
  | a ternary whose predicate is a nested condition has that
  | condition's leaves recorded first, as operands 0 and 1
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id) ? :ok : :no
      end
    RUBY
    both = condition('&&', 16...23, 27...35, extent: 16...35)
    arms = [arm(:then, 38...41), arm(:else, 44...47)]
    ternary = condition('?:', both, *arms, extent: 16...47)
    decisions = { 'k.rb:2:2' => ternary }
    expected = [
      'def kata?(id)',
      '  PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 2), ' \
      'PathCoverage.record("k.rb:2:2", 0, ok?(id)) && ' \
      'PathCoverage.record("k.rb:2:2", 1, new?(id)) ' \
      '? :ok : :no)',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Kd4', %w(
  | the leaves of a condition folded in as a ternary's arm
  | are recorded under the ternary's decision, numbered on from
  | its predicate's
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) ? new?(id) && id.size == 6 : :no
      end
    RUBY
    both = condition('&&', 26...34, 38...50, extent: 26...50)
    ternary = condition(
      '?:', 16...23, arm(:then, 26...50, both), arm(:else, 53...56),
      extent: 16...56
    )
    decisions = { 'k.rb:2:2' => ternary }
    expected = [
      'def kata?(id)',
      '  PathCoverage.leave(' \
      'PathCoverage.enter("k.rb:2:2", 3), ' \
      'PathCoverage.record("k.rb:2:2", 0, ok?(id)) ? ' \
      'PathCoverage.record("k.rb:2:2", 1, new?(id)) && ' \
      'PathCoverage.record("k.rb:2:2", 2, id.size == 6) : :no)',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, decisions)
  end

  test '6D1Kr1', %w(
  | Example: ship, a write then a value, each reached
  | Each reached statement has a reach call put before it,
  | on the same line, naming it, so each run counts it.
  ) do
    source = <<~RUBY
      def ship(order)
        box = order.pack
        box
      end
    RUBY
    reaches = { 'k.rb:2:2' => 18, 'k.rb:3:2' => 37 }
    expected = [
      'def ship(order)',
      '  PathCoverage.reach("k.rb:2:2"); box = order.pack',
      '  PathCoverage.reach("k.rb:3:2"); box',
      'end',
      ''
    ].join("\n")
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, {}, reaches)
  end

  test '6D1Kr2', %w(
  | Example: zero, an endless def of 0, reached by its range
  | Its reach call and its body are wrapped together in
  | parentheses, so the def still returns its body's value.
  ) do
    source = "def zero = 0\n"
    reaches = { 'k.rb:1:11' => 11...12 }
    expected = "def zero = (PathCoverage.reach(\"k.rb:1:11\"); 0)\n"
    rewriter = PathCoverage::Rewriter
    assert_equal expected, rewriter.rewrite(source, {}, reaches)
  end
end
