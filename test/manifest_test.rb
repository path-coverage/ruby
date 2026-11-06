require_relative 'test_helper'
require 'path_coverage/manifest'

class ManifestTest < TidTest
  test '6asy10', %w(
  | each && decision in a file is found without running it,
  | with the byte range of each of its operands, so an &&
  | that never runs can still be reported as missed, and
  | the rewriter and reporters need no parse of their own
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id)
      end
    RUBY
    # ok?(id) is bytes 16...23, new?(id) is bytes 27...35
    both = condition('&&', 16...23, 27...35, extent: 16...35)
    expected = { 'k.rb:2:2' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy20', %w(
  | each || decision is found too, named by its operator,
  | with the byte range of each of its operands
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) || new?(id)
      end
    RUBY
    either = condition('||', 16...23, 27...35, extent: 16...35)
    expected = { 'k.rb:2:2' => either }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy30', %w(
  | a chain of one operator is a single decision,
  | flat, with one operand per link in the chain
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id) && id.size == 6
      end
    RUBY
    operands = [16...23, 27...35, 39...51]
    chain = condition('&&', *operands, extent: 16...51)
    expected = { 'k.rb:2:2' => chain }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy40', %w(
  | an operand that is itself a condition of the other operator
  | nests inside its decision as Ruby's precedence groups it,
  | rather than being a decision of its own
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id) || id.size == 6
      end
    RUBY
    both = condition('&&', 16...23, 27...35, extent: 16...35)
    either = condition('||', both, 39...51, extent: 16...51)
    expected = { 'k.rb:2:2' => either }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy50', %w(
  | a condition grouped in parentheses nests inside its decision
  | as the parentheses group it, the parentheses themselves
  | being no part of the tree since they decide nothing
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && (new?(id) || id.size == 6)
      end
    RUBY
    # the decision's extent takes in the closing parenthesis
    either = condition('||', 28...36, 40...52, extent: 28...52)
    both = condition('&&', 16...23, either, extent: 16...53)
    expected = { 'k.rb:2:2' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy60', %w(
  | parentheses holding several statements are one leaf
  | operand, since only their last statement's value decides
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && (log(id); new?(id))
      end
    RUBY
    both = condition('&&', 16...23, 27...46, extent: 16...46)
    expected = { 'k.rb:2:2' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy70', %w(
  | empty parentheses are one leaf operand, always nil
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && ()
      end
    RUBY
    both = condition('&&', 16...23, 27...29, extent: 16...29)
    expected = { 'k.rb:2:2' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy75', %w(
  | a decision is named by its operator as written,
  | so and and or are not shown as && and ||
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) and new?(id) or id.size == 6
      end
    RUBY
    both = condition('and', 16...23, 28...36, extent: 16...36)
    either = condition('or', both, 40...52, extent: 16...52)
    expected = { 'k.rb:2:2' => either }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy77', %w(
  | a leaf that is a command call, eg id.include? 'N' after
  | an and, is named among the condition's commands, since
  | it needs parentheses of its own to be an argument
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) and id.include? 'N'
      end
    RUBY
    decision = condition(
      'and', 16...23, 28...43, commands: [28...43], extent: 16...43
    )
    expected = { 'k.rb:2:2' => decision }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy78', %w(
  | a leaf that can only be truthy, eg MonotonicClock.new,
  | is named among the condition's fixed leaves, so its
  | never false is not reported as a gap
  ) do
    source = <<~RUBY
      def initialize(options)
        @clock = options[:clock] || MonotonicClock.new
      end
    RUBY
    fixed = { 54...72 => :truthy }
    decision = condition('||', 35...50, 54...72, fixed:,
                                                 extent: 35...72)
    expected = { 'k.rb:2:11' => decision }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy7c', %w(
  | Example: options[:clock] or MonotonicClock.new 'UTC'
  | MonotonicClock.new 'UTC' is a command call.
  | So it is named among the condition's commands.
  | It is a call to new, so it can only be truthy.
  | So it is named among the condition's fixed leaves too.
  ) do
    source = <<~RUBY
      def clock(options)
        options[:clock] or MonotonicClock.new 'UTC'
      end
    RUBY
    decision = condition(
      'or', 21...36, 40...64,
      commands: [40...64], fixed: { 40...64 => :truthy },
      extent: 21...64
    )
    expected = { 'k.rb:2:2' => decision }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy79', %w(
  | literals and lambdas can only be truthy, and nil and false
  | only falsy, so each is a fixed leaf with that outcome
  ) do
    source = <<~RUBY
      def defaults(o)
        @a = o[:a] || 'anon'
        @b = o[:b] || 1
        @c = o[:c] || :none
        @d = o[:d] || []
        @e = o[:e] || {}
        @f = o[:f] || true
        @g = o[:g] || -> { 0 }
        @h = o[:h] || nil
        @i = o[:i] || false
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    fixed = decisions.values.map(&:fixed).reduce({}, :merge)
    actual = fixed.transform_keys { |range| source.byteslice(range) }
    expected = {
      "'anon'" => :truthy, '1' => :truthy, ':none' => :truthy,
      '[]' => :truthy, '{}' => :truthy, 'true' => :truthy,
      '-> { 0 }' => :truthy, 'nil' => :falsy, 'false' => :falsy
    }
    assert_equal expected, actual
  end

  test '6asy7a', %w(
  | a constant, eg LATEST or Config::DEFAULT, is no fixed
  | leaf, since it can hold nil or false, eg VERBOSE = false
  ) do
    source = <<~RUBY
      def tagged(match)
        tag = match[8] || LATEST
        host = match[2] || Config::DEFAULT
        "\#{host}:\#{tag}"
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal [{}, {}], decisions.values.map(&:fixed)
  end

  test '6asy7b', %w(
  | $stdout and $stderr are truthy only, as Ruby refuses nil
  | or false for either; $stdin accepts both, so it is not
  | fixed
  ) do
    source = <<~RUBY
      def streams
        out = Thread.current[:out] || $stdout
        err = Thread.current[:err] || $stderr
        inp = Thread.current[:inp] || $stdin
        [out, err, inp]
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    fixed = decisions.values.map(&:fixed).reduce({}, :merge)
    actual = fixed.transform_keys { |range| source.byteslice(range) }
    expected = { '$stdout' => :truthy, '$stderr' => :truthy }
    assert_equal expected, actual
  end

  test '6asy80', %w(
  | a condition inside a leaf operand, eg in a block,
  | decides something else, so it is a decision of its own
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && ids.each { |k| k && k.ok? }
      end
    RUBY
    outer = condition('&&', 16...23, 27...54, extent: 16...54)
    inner = condition('&&', 42...43, 47...52, extent: 42...52)
    expected = { 'k.rb:2:2' => outer, 'k.rb:2:28' => inner }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy90', %w(
  | a ternary is a choice too, so it is a decision, named ?:,
  | whose operands are its predicate and its two arms, and
  | whose extent is the whole ternary
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) ? :ok : :no
      end
    RUBY
    arms = [arm(:then, 26...29), arm(:else, 32...35)]
    ternary = condition('?:', 16...23, *arms, extent: 16...35)
    expected = { 'k.rb:2:10' => ternary }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy91', %w(
  | a ternary whose predicate is an && is a decision of one leaf,
  | its predicate, and the && a decision of its own, as a block
  | method's call wholly a leaf is: each a row of its own card,
  | the card's tree saying what the &&'s paths give that leaf
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) && new?(id) ? :ok : :no
      end
    RUBY
    both = condition('&&', 16...23, 27...35, extent: 16...35)
    arms = [arm(:then, 38...41), arm(:else, 44...47)]
    ternary = condition('?:', 16...35, *arms, extent: 16...47)
    expected = { 'k.rb:2:22' => ternary, 'k.rb:2:2' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy92', %w(
  | a condition that is a ternary's arm is part of the one
  | expression, so it folds into the ternary's decision as that
  | arm's body, and a plain arm is an arm with no body
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
    expected = { 'k.rb:2:10' => ternary }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy93', %w(
  | a condition that is a ternary's else arm folds into the
  | ternary's decision too
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) ? :ok : new?(id) && id.size == 6
      end
    RUBY
    both = condition('&&', 32...40, 44...56, extent: 32...56)
    ternary = condition(
      '?:', 16...23, arm(:then, 26...29), arm(:else, 32...56, both),
      extent: 16...56
    )
    expected = { 'k.rb:2:10' => ternary }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy94', %w(
  | a condition inside a plain arm, eg in a block, decides
  | something else, so it is a decision of its own, after the
  | ternary's
  ) do
    source = <<~RUBY
      def kata?(id)
        ok?(id) ? ids.each { |k| k && k.ok? } : :no
      end
    RUBY
    ternary = condition(
      '?:', 16...23, arm(:then, 26...53), arm(:else, 56...59),
      extent: 16...59
    )
    inner = condition('&&', 41...42, 46...51, extent: 41...51)
    expected = { 'k.rb:2:10' => ternary, 'k.rb:2:27' => inner }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asy95', %w(
  | a ternary that is an arm of a ternary, in parentheses,
  | is a decision of its own, the arm holding it a plain arm, as an
  | if's arm holding an if is: each is a row of its own card,
  | the card's tree placing the inner in the outer's then arm.
  | Each is named at its ?, so a ternary never shares the name
  | of a decision starting where it does, eg its predicate's.
  ) do
    source = <<~RUBY
      def k(x, y)
        x ? (y ? 1 : 2) : 3
      end
    RUBY
    inner = condition(
      '?:', 19...20, arm(:then, 23...24), arm(:else, 27...28),
      extent: 19...28
    )
    outer = condition(
      '?:', 14...15, arm(:then, 18...29), arm(:else, 32...33),
      extent: 14...33
    )
    expected = { 'k.rb:2:4' => outer, 'k.rb:2:9' => inner }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya0', %w(
  | Example: if order.big? && order.new?
  | The if is a decision, named if.
  | Its first operand is its predicate, one leaf.
  | Here that is the &&, a decision of its own, named where it
  | starts.
  | Its other operands are its then arm (5) and else arm (7).
  | Its extent is "if order.big? && order.new?".
  | The arms are outside the extent, as they are statements.
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
    both = condition('&&', 20...30, 34...44, extent: 20...44)
    choice = condition(
      'if', 20...44, arm(:then, 49...50), arm(:else, 62...63),
      extent: 17...44
    )
    expected = { 'k.rb:2:2' => choice, 'k.rb:2:5' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya1', %w(
  | Example: if order.big? 5 end
  | A predicate of a single operand still makes a decision.
  | With no else, the if has a then arm only.
  ) do
    source = <<~RUBY
      def fee(order)
        if order.big?
          5
        end
      end
    RUBY
    choice = condition(
      'if', 20...30, arm(:then, 35...36), extent: 17...30
    )
    expected = { 'k.rb:2:2' => choice }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya2', %w(
  | Example: if order.big? 5 elsif order.new? 6 end
  | The elsif is a decision of its own, named at elsif.
  | The if's else arm is the whole elsif.
  ) do
    source = <<~RUBY
      def fee(order)
        if order.big?
          5
        elsif order.new?
          6
        end
      end
    RUBY
    outer = condition(
      'if', 20...30, arm(:then, 35...36), arm(:else, 39...67),
      extent: 17...30
    )
    inner = condition(
      'if', 45...55, arm(:then, 60...61), extent: 39...55
    )
    expected = { 'k.rb:2:2' => outer, 'k.rb:4:2' => inner }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya3', %w(
  | Example: if x else end
  | Neither arm has any statements.
  | Each is still an arm, as taking it is still a path.
  | Each arm's extent is nil.
  ) do
    source = <<~RUBY
      def k(x)
        if x
        else
        end
      end
    RUBY
    choice = condition(
      'if', 14...15, arm(:then, nil), arm(:else, nil), extent: 11...15
    )
    expected = { 'k.rb:2:2' => choice }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya4', %w(
  | Example: unless order.big? 5 else 7 end
  | An unless is a decision, named unless, just like an if.
  | Its then arm (5) runs when order.big? is false.
  | Its extent is "unless order.big?".
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
    choice = condition(
      'unless', 24...34, arm(:then, 39...40), arm(:else, 52...53),
      extent: 17...34
    )
    expected = { 'k.rb:2:2' => choice }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya5', %w(
  | Example: return 1 unless a && b
  | The decision is named at the column of unless (11).
  | It is not named at the column of return (2).
  | Its then arm is "return 1", the code left of the unless.
  | Its extent is "unless a && b".
  | Its predicate, a && b, is one leaf, the && a decision of its own.
  ) do
    source = <<~RUBY
      def k(a, b)
        return 1 unless a && b
      end
    RUBY
    both = condition('&&', 30...31, 35...36, extent: 30...36)
    choice = condition(
      'unless', 30...36, arm(:then, 14...22), extent: 23...36
    )
    expected = { 'k.rb:2:11' => choice, 'k.rb:2:18' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya6', %w(
  | Example: return :ok if ok?(id)
  | A modifier if is a decision too.
  | It is named at the column of if (13).
  ) do
    source = <<~RUBY
      def group?(id)
        return :ok if ok?(id)
      end
    RUBY
    choice = condition(
      'if', 31...38, arm(:then, 17...27), extent: 28...38
    )
    expected = { 'k.rb:2:13' => choice }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya7', %w(
  | Example: case x when 1, 2 ... when String ... else ... end
  | A case with a subject (x) is a decision, named case.
  | Each when is an arm.
  | Its condition is a when over its patterns, eg 1 and 2.
  | The else is an arm too.
  | A pattern is matched against x, not tested for truth.
  | So a literal pattern, eg 1, is not fixed as always true.
  | Its extent is "case x".
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
    small = condition('when', 28...29, 31...32, extent: 28...32)
    text = condition('when', 51...57, extent: 51...57)
    choice = condition(
      'case',
      arm(:when, 37...43, small), arm(:when, 62...67, text),
      arm(:else, 79...85),
      extent: 14...20
    )
    expected = { 'k.rb:2:2' => choice }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asya8', %w(
  | Example: case when x && all ... end
  | A case with no subject is not a decision.
  | Example: case x when *all ... end
  | A case with a splat pattern is not a decision either.
  | The x && all inside the first case is still a decision.
  ) do
    source = <<~RUBY
      def kind(x, all)
        case
        when x && all
          1
        end
        case x
        when *all
          2
        end
      end
    RUBY
    both = condition('&&', 31...32, 36...39, extent: 31...39)
    expected = { 'k.rb:3:7' => both }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asybb', %w(
  | Example: case x when 1 ... when 2, *more ... end
  | A splat among a later when's patterns, after a plain one,
  | makes the case no decision, as one in its first when does.
  ) do
    source = <<~RUBY
      def kind(x, more)
        case x
        when 1 then :one
        when 2, *more then :many
        end
      end
    RUBY
    assert_equal({}, PathCoverage::Manifest.decisions(source, 'k.rb'))
  end

  test '6asya9', %w(
  | Example: case x when 1 then :one end
  | With no else, the case has its when arms only.
  ) do
    source = <<~RUBY
      def k(x)
        case x
        when 1 then :one
        end
      end
    RUBY
    one = condition('when', 25...26, extent: 25...26)
    choice = condition(
      'case', arm(:when, 32...36, one), extent: 11...17
    )
    expected = { 'k.rb:2:2' => choice }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asyb0', %w(
  | Example: ids.any? { |id| id.ok? }
  | The call is a decision, named any?.
  | It is named at the column of any? (6), not of ids.
  | So in ids.select {...}.any? {...} each call has its own
  | decision.
  | Its leaves are its receiver (ids) and its block's
  | expression (id.ok?).
  | Its extent is the whole call.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.any? { |id| id.ok? }
      end
    RUBY
    found = condition('any?', 13...16, 29...35, extent: 13...37)
    expected = { 'k.rb:2:6' => found }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asyb1', %w(
  | A block method's call is not a decision when:
  | it has arguments, eg ids.any?(Integer) { ... }
  | it has no receiver, eg any? { ... }
  | it has no block, eg ids.any?
  | its block is an argument, eg ids.any?(&:ok?)
  | its block is empty, eg ids.none? {}
  | its block has two expressions, eg { id.ok?; id.new? }
  | it is called with &., eg ids&.find { ... }
  | In each of these its block's calls cannot all be seen.
  | The call with &. is a &. chain decision instead, its one leaf
  | ids, nil or not nil.
  ) do
    source = <<~RUBY
      def k(ids, x)
        ids.any?(Integer) { |id| id.ok? }
        any? { |id| id.ok? }
        ids.any?
        ids.any?(&:ok?)
        ids.none? {}
        ids.all? { |id| id.ok?; id.new? }
        ids&.find { |id| id.ok? }
      end
    RUBY
    chain = condition('&.', 155...158, extent: 155...180)
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal({ 'k.rb:8:2' => chain }, actual)
  end

  test '6asyb2', %w(
  | Example: ids.all? { |id| id.include? 'N' }
  | The block's expression is a command call (no parentheses).
  | Example: ids.none? { |id| id.ok? or id.new? }
  | The block's expression is an or.
  | Neither can be a bare argument to a method.
  | So each is noted in its decision's commands.
  | That makes the rewriter parenthesise it.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.all? { |id| id.include? 'N' }
        ids.none? { |id| id.ok? or id.new? }
      end
    RUBY
    command = 29...44
    word = 66...83
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    # the or is a decision of its own too, with no commands
    expected = [[command], [word], []]
    assert_equal expected, decisions.values.map(&:commands)
  end

  test '6asyb3', %w(
  | Example: ids.select { |id| id.ok? }
  | select calls its block with every item.
  | It is a decision too, just like any?.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.select { |id| id.ok? }
      end
    RUBY
    kept = condition('select', 13...16, 31...37, extent: 13...39)
    expected = { 'k.rb:2:6' => kept }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asybc', %w(
  | Example: a && xs.any? { |x| x.odd? }
  | A leaf that is wholly a block method's call whose value
  | follows from its path is a decision of its own, as a ?: in a
  | ?:'s arm is, the leaf holding it a plain leaf: each is a
  | row of its own card, the card's tree saying what the call's
  | paths give the leaf.
  ) do
    source = <<~RUBY
      def k(a, xs)
        a && xs.any? { |x| x.odd? }
      end
    RUBY
    both = condition('&&', 15...16, 20...42, extent: 15...42)
    any = condition('any?', 20...22, 34...40, extent: 20...42)
    expected = { 'k.rb:2:2' => both, 'k.rb:2:10' => any }
    actual = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal expected, actual
  end

  test '6asyb4', %w(
  | Example: a block whose one expression is a modifier unless,
  | a modifier if, or a rescue modifier
  | None of these can be a bare argument.
  | So each is noted among its decision's commands, to be
  | parenthesised when it is wrapped.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.filter_map { |id| id.name unless id.nil? }
        ids.select { |id| id if id.ok? }
        ids.count { |id| id.ok? rescue false }
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    commands = decisions.values.flat_map(&:commands)
    texts = commands.map { |range| source.byteslice(range) }
    expected = [
      'id.name unless id.nil?', 'id if id.ok?', 'id.ok? rescue false'
    ]
    assert_equal expected, texts
  end

  test '6asyba', %w(
  | Example: a block whose one expression is a ternary, and one
  | whose one expression is an if ... end
  | Neither is a modifier: each can be a bare argument.
  | So neither is noted among its decision's commands.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.count { |id| id.ok? ? id.big? : false }
        ids.select { |id| if id.ok? then id.big? else false end }
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    assert_equal [], decisions.values.flat_map(&:commands)
  end

  test '6asyb5', %w(
  | Example: a block whose one expression is break, next or
  | return
  | Such an expression is no value, so it cannot be wrapped,
  | even in parentheses.
  | So such a block method's call is no decision.
  ) do
    source = <<~RUBY
      def k(ids)
        ids.find { |id| break id }
        ids.select { |id| next true }
        ids.any? { |id| return true }
      end
    RUBY
    assert_equal({}, PathCoverage::Manifest.decisions(source, 'k.rb'))
  end

  test '6asyb6', %w(
  | Example: @clock ||= Clock.new(a && b) with ||= ignored
  | The write is no decision.
  | The && on its right side still is.
  ) do
    source = <<~RUBY
      def k(a, b)
        @clock ||= Clock.new(a && b)
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb',
                                                 ['||='])
    assert_equal ['&&'], decisions.values.map(&:operator)
  end

  test '6asyb7', %w(
  | Example: a select whose do block rescues
  | Its block's body is its statements and its rescue, not one
  | expression, so it cannot be wrapped.
  | So the select is no decision.
  ) do
    source = <<~RUBY
      def valid(ids)
        ids.select do |id|
          Integer(id).positive?
        rescue ArgumentError
          false
        end
      end
    RUBY
    assert_equal({}, PathCoverage::Manifest.decisions(source, 'k.rb'))
  end

  test '6asyb8', %w(
  | Example: an if comparing a select's size with a reject's
  | Its predicate is one leaf with two block calls inside it.
  | So the leaf contains both, select then reject, in the
  | order they run, then its own outcome.
  ) do
    source = <<~RUBY
      def mostly_odd?(ids)
        if ids.select { |id| id.odd? }.size > ids.reject { |id| id.odd? }.size
          true
        end
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    predicate = decisions.values.first.operands.first
    operators = predicate.operands.first(2).map(&:operator)
    assert_equal ['contains', %w(select reject)],
                 [predicate.operator, operators]
  end

  test '6asyb9', %w(
  | Example: ready? && order, ready? a call with no receiver
  | A call of the method's own, with no receiver or arguments,
  | is a plain leaf, as is order.
  ) do
    source = <<~RUBY
      def ship(order)
        ready? && order
      end
    RUBY
    decision = PathCoverage::Manifest.decisions(source,
                                                'k.rb').values.first
    assert_equal ['&&', [Range, Range]],
                 [decision.operator, decision.operands.map(&:class)]
  end
end
