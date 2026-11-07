require_relative 'test_helper'
require 'path_coverage/card_tree'
require 'path_coverage/card_ways'

class CardTreeTest < TidTest
  test 'Ct8e01', %w(
  | Example: pick, an if of a && b holding an if of b, each arm
  | of which returns
  | Each row of pick's card names its parent, the decision whose
  | arm it is in, that arm, and on, the parent's possible paths
  | it runs on, by their index: the inner if runs only on the
  | outer's one path that takes its then arm. A row at the top
  | of the method has none of these. The &&, the outer if's
  | predicate, is a row in that if's one leaf, giving it true
  | only where a and b are.
  ) do
    source = <<~RUBY
      def pick(a, b)
        if a && b
          if b then return 1 else return 2 end
        end
      end
    RUBY
    expected = {
      '2:2' => [nil, nil, nil, nil, nil],
      '2:5' => ['2:2', nil, [0, 1], 0, [true, false, false]],
      '3:4' => ['2:2', 'then', [0], nil, nil],
      '3:14' => ['3:4', 'then', [0], nil, nil],
      '3:28' => ['3:4', 'else', [1], nil, nil]
    }
    assert_equal expected, places(source)
  end

  test 'Ct8e02', %w(
  | Example: kept, an && of a and a select's any?, its block a ?:
  | A row inside a leaf of its parent is in no arm, and runs on
  | each of its parent's paths that evaluate that leaf: the ?:
  | runs only where select called its block with an item, not
  | where a was false, nor where select had 0 items.
  | It is the whole of its leaf, select's block, so gives what
  | its paths give it: not known, as neither arm's truthiness
  | is noted.
  ) do
    source = <<~RUBY
      def kept(xs, a)
        a && xs.select { |x| x ? 1 : nil }.any?
      end
    RUBY
    expected = {
      '2:2' => [nil, nil, nil, nil, nil],
      '2:25' => ['2:2', nil, (2..11).to_a, 2, [nil, nil]]
    }
    assert_equal expected, places(source)
  end

  test 'Ct8e03', %w(
  | Example: odd, an if of a with an empty then arm, a ?: in its else
  | An arm with no statements holds no row, so the ?: is placed
  | in the else, on the if's false path.
  ) do
    source = <<~RUBY
      def odd(a, b)
        if a
        else
          b ? 1 : 2
        end
      end
    RUBY
    expected = {
      '2:2' => [nil, nil, nil, nil, nil],
      '4:6' => ['2:2', 'else', [1], nil, nil]
    }
    assert_equal expected, places(source)
  end

  test 'Ct8e04', %w(
  | Example: each_if, an && of a and a ?: of b whose then arm
  | is an each whose block is a ?: of x
  | A row inside an arm of a condition nested in its parent
  | runs only on the parent's paths that take that arm: the ?:
  | of x runs where a and b were both true, whatever the &&'s
  | value.
  ) do
    source = <<~RUBY
      def each_if(a, b, xs)
        a && (b ? xs.each { |x| x ? 1 : 2 } : 3)
      end
    RUBY
    expected = {
      '2:2' => [nil, nil, nil, nil, nil],
      '2:28' => ['2:2', 'then', [0, 1], 2, nil]
    }
    assert_equal expected, places(source)
  end

  test 'Ct8e08', %w(
  | Example: fee, an if holding a ?: of an &&; two, two ?:s one
  | after another; led?, an || of an any? whose block is an &&
  | The ways through a card fold its tree: rows one after
  | another multiply, and a decision adds up its paths, each times
  | the ways of the rows it runs on that path; a row that is the
  | whole of a leaf counts only its paths that give the leaf the
  | outcome the path has.
  | fee: then 3, else 1, so 4. two: 2 times 2, so 4. led?: the
  | ||'s true path takes the 2 any? paths giving true, 1 way
  | each; each false path takes its 3 giving false, 1 + 2 + 2.
  ) do
    source = <<~RUBY
      def fee(member, paid, big)
        if member
          paid && big ? 5 : 10
        else
          0
        end
      end
      def two(a, b)
        x = a ? 1 : 2
        y = b ? 3 : 4
        [x, y]
      end
      def led?(xs)
        xs.any? { |x| x.odd? && x > 1 } || xs.empty?
      end
    RUBY
    expected = { 'k.rb:1:0' => 4, 'k.rb:8:0' => 4, 'k.rb:13:0' => 12 }
    assert_equal expected, PathCoverage::CardWays.of(source, 'k.rb')
  end

  test 'Ct8e09', %w(
  | Example: guard, a return modifier then a ?:; twice, two
  | return modifiers on one line then a value; early, an if
  | whose then arm returns, then a ?:; must, a raise unless
  | modifier then a ?:
  | A way that returns or raises leaves the method there, so it
  | goes on to none of the rows after it: each is 3 ways, the
  | one that leaves early and the 2 that go on, not 2 times 2.
  ) do
    source = <<~RUBY
      def guard(a, b)
        return 0 if a
        b ? 1 : 2
      end
      def twice(a, b)
        return 0 if a; return 1 if b
        2
      end
      def early(a, b)
        if a
          return 1
        end
        b ? 1 : 2
      end
      def must(a, b)
        raise 'no' unless a
        b ? 1 : 2
      end
    RUBY
    defs = %w(k.rb:1:0 k.rb:5:0 k.rb:9:0 k.rb:15:0)
    expected = defs.to_h { [_1, 3] }
    assert_equal expected, PathCoverage::CardWays.of(source, 'k.rb')
  end

  test 'Ct8e10', %w(
  | Example: guard, a return modifier on a, then a ?: on b
  | Folded in WayAlgebras::Listed, a card gives its ways
  | themselves, each the [row, path] it takes at every row it
  | reaches, path the index of the row's possible path: the way
  | that returns at the modifier, and the two that go on to each
  | path of the ?:.
  ) do
    source = <<~RUBY
      def guard(a, b)
        return 0 if a
        b ? 1 : 2
      end
    RUBY
    expected = [
      [['2:11', 0]],
      [['2:11', 1], ['3:4', 0]],
      [['2:11', 1], ['3:4', 1]]
    ]
    assert_equal expected, listed(source)
  end

  test 'Ct8e11', %w(
  | Example: f, a guard on a, an if on b holding a ?: on b, then
  | an && of a and b; g, a && b || a && c; h, a guard on a && b,
  | then a ?: on a && b
  | A local variable no code in its method writes, eg a
  | parameter, has one outcome all through a call, so a way
  | needing it true at one leaf and false at another is no way.
  | f: 1 way returns at the guard; past it a is false, so the ?:
  | takes only its true path, and the && only its false one:
  | 1 + 2 * 1 = 3, not 1 + 3 * 3. g: of its 7 paths, the 3 with
  | a both true and false are none: 4. h: past the guard, a true
  | means b false, so each of its 2 ways goes on to the ?:'s
  | false path alone: 1 + 2 = 3, not 1 + 2 * 3.
  ) do
    source = <<~RUBY
      def f(a, b)
        return 0 if a
        if b
          x = b ? 1 : 2
        end
        a && b
      end
      def g(a, b, c) = a && b || a && c
      def h(a, b)
        return 0 if a && b
        a && b ? 1 : 2
      end
    RUBY
    expected = { 'k.rb:1:0' => 3, 'k.rb:8:0' => 4, 'k.rb:9:0' => 3 }
    assert_equal expected, PathCoverage::CardWays.of(source, 'k.rb')
  end

  test 'Ct8e12', %w(
  | Example: each a guard, then a ?: on what looks the same: w,
  | a local written after the guard; c, a call; i, an instance
  | variable; e, a local in a method calling binding; s, a
  | block's own a, shadowing the method's
  | Where the code cannot show that two leaves have the same
  | outcome, no way is ruled out: a write, a call, or code
  | outside the method may change it between them, and a block's
  | parameter is another variable. Each keeps 1 + 2 ways, s its
  | 1 + 7.
  ) do
    source = <<~RUBY
      def w(a)
        return 0 if a
        a = !a
        a ? 1 : 2
      end
      def c(x)
        return 0 if x.ok?
        x.ok? ? 1 : 2
      end
      def i
        return 0 if @a
        @a ? 1 : 2
      end
      def e(a)
        return 0 if a
        binding.local_variable_set(:a, 1)
        a ? 1 : 2
      end
      def s(a, xs)
        return 0 if a
        xs.any? { |a| a && a.odd? }
      end
    RUBY
    expected = {
      'k.rb:1:0' => 3, 'k.rb:6:0' => 3, 'k.rb:10:0' => 3,
      'k.rb:14:0' => 3, 'k.rb:19:0' => 8
    }
    assert_equal expected, PathCoverage::CardWays.of(source, 'k.rb')
  end

  test 'Ct8e07', %w(
  | Example: led?, an || of an any? and xs.empty?
  | The || starts where the any?'s receiver, xs, does, yet it is
  | the any?'s parent, not its child: a decision is placed where its
  | whole code lies, not just where it starts.
  ) do
    source = <<~RUBY
      def led?(xs)
        xs.any? { |x| x.odd? } || xs.empty?
      end
    RUBY
    gives = [false, true, false, true, false]
    expected = {
      '2:2' => [nil, nil, nil, nil, nil],
      '2:5' => ['2:2', nil, [0, 1, 2], 0, gives]
    }
    assert_equal expected, places(source)
  end

  test 'Ct8e06', %w(
  | Example: big?, an && of a and an any? whose block compares
  | each item with a ?:
  | A row in a leaf of its parent names that leaf, by its
  | index. A row that is the whole of that leaf, as the any? is,
  | also names what each of its own possible paths gives the
  | leaf: the any?'s value, false with 0 items, else its last
  | answer. The ?: in the any?'s block is inside a leaf, not all
  | of it, so gives nothing.
  ) do
    source = <<~RUBY
      def big?(a, xs, lim)
        a && xs.any? { |x| x > (lim ? 1 : 2) }
      end
    RUBY
    gives = [false, true, false, true, false]
    expected = {
      '2:2' => [nil, nil, nil, nil, nil],
      '2:10' => ['2:2', nil, [0, 1], 1, gives],
      '2:30' => ['2:10', nil, [1, 2, 3, 4], 1, nil]
    }
    assert_equal expected, places(source)
  end

  test 'Ct8e05', %w(
  | Example: every Ruby file of the gem's lib and test, and of
  | its demo's source
  | Every row placed in a parent is placed in a row of its own
  | card, on some of that parent's possible paths and on none
  | it does not have: no row hangs from nothing, or runs on no
  | path at all. And no row is its own ancestor: following
  | parents from any row reaches the top.
  ) do
    root = File.expand_path('..', __dir__)
    globs = %w(lib/**/*.rb test/*.rb demo/source/*.rb)
    files = globs.flat_map { Dir.glob(_1, base: root) }.sort
    misplaced = files.to_h do |file|
      [file, misplaced_in(File.read("#{root}/#{file}"))]
    end
    assert_equal files.to_h { [_1, []] }, misplaced
  end

  private

  # The ways through source's one card, its def's on line 1, as
  # if source were k.rb, as WayAlgebras::Listed folds them, each
  # way's labels in order, and the ways in order.
  def listed(source)
    listed = PathCoverage::WayAlgebras::Listed
    ways = PathCoverage::CardWays.of(source, 'k.rb', listed)
    ways['k.rb:1:0'].map(&:sort).sort
  end

  # [parent, in, on, leaf, gives] of each row of source's one
  # card, its def's on line 1, as if source were k.rb.
  def places(source)
    rows = PathCoverage::CardTree.of(source, 'k.rb')['k.rb:1:0']
    rows.transform_values do |place|
      place.values_at('parent', 'in', 'on', 'leaf', 'gives')
    end
  end

  # The misfits, as misfits gives them, of every card of source,
  # as if it were k.rb.
  def misplaced_in(source)
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    tree = PathCoverage::CardTree.of(source, 'k.rb', decisions)
    tree.values.flat_map do |rows|
      inner = rows.values - [PathCoverage::CardTree::TOP]
      misfits(rows.keys, inner, decisions) + looped(rows)
    end
  end

  # The key each row of rows, a card's places, reaches after as
  # many steps up its parents as rows has rows: none, unless some
  # row is its own ancestor, as every other walk reaches the top.
  def looped(rows)
    reached = rows.keys.map do |key|
      rows.size.times.reduce(key) { |at, _| rows.dig(at, 'parent') }
    end
    reached.compact
  end

  # Each parent of inner, the places of a card's rows that have
  # one, that is none of keys, its rows' keys; true for each
  # place on no path; and each path a place is on that its
  # parent, among decisions, does not have.
  def misfits(keys, inner, decisions)
    parents = inner.map { _1['parent'] } - keys
    empty = inner.map { _1['on'].empty? } - [false]
    beyond = inner.flat_map do |place|
      parent = decisions["k.rb:#{place['parent']}"]
      place['on'] - [*0...PathCoverage::DecisionPaths.possible(parent).size]
    end
    [*parents, *empty, *beyond]
  end
end
