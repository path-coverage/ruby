require_relative 'test_helper'
require 'path_coverage/card_ways'
require 'path_coverage/method_statements'
require 'path_coverage/card_context'

class MethodStatementsTest < TidTest
  test 'St3e01', %w(
  | Example: total, a write, a call chain and a value as its
  | top-level statements
  | None shapes its paths: each runs exactly when the method
  | does, so none is a row.
  ) do
    source = <<~RUBY
      def total(order)
        sum = order.subtotal
        order.items.first.save
        sum
      end
    RUBY
    assert_equal [], statements(source)['k.rb:1:0']
  end

  test 'St3e02', %w(
  | Example: refuse, logging then raising, and first,
  | returning its items' first
  | A raise is named raise, not (), though it is a call,
  | as it leaves the method, and so is a row, as a return is,
  | named return: each ends a path. The log call is no row.
  ) do
    source = <<~RUBY
      def refuse(order)
        order.log('refused')
        raise ArgumentError, 'refused'
      end

      def first(items)
        return items.first
      end
    RUBY
    tops = statements(source).transform_values do |rows|
      rows.map(&:top)
    end
    expected = {
      'k.rb:1:0' => ['raise'], 'k.rb:6:0' => ['return']
    }
    assert_equal expected, tops
  end

  test 'St3e03', %w(
  | Example: a class with an empty initialize
  | initialize has no statements, so no rows.
  ) do
    source = <<~RUBY
      class Feed
        def initialize; end
      end
    RUBY
    assert_equal({ 'k.rb:2:2' => [] }, statements(source))
  end

  test 'St3e04', %w(
  | Example: ship, an if statement then a value
  | The if is a decision, so its row is named by its operator,
  | if, as decision mode names it.
  | The call in its then, and the value, are no rows.
  ) do
    source = <<~RUBY
      def ship(order)
        if order.paid?
          order.pack
        end
        order
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 2, 'if']], rows
  end

  test 'St3e05', %w(
  | Example: label, writing a ternary's value then returning it
  | A write is looked through, so its row is the ternary's:
  | named ?: and at the ternary's ?, as decision mode names
  | it, not at the write's.
  ) do
    source = <<~RUBY
      def label(items)
        text = items.empty? ? 'none' : 'some'
        text
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 22, '?:']], rows
  end

  test 'St3e06', %w(
  | Example: discount, adding two ternaries' values
  | + imposes no flow, so it is looked through, as is the
  | write and each parenthesis, giving a row for each
  | ternary, in the order they run.
  ) do
    source = <<~RUBY
      def discount(big, member)
        total = (big ? 10 : 0) + (member ? 5 : 0)
        total
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 15, '?:'], [2, 35, '?:']], rows
  end

  test 'St3e07', %w(
  | Example: price, returning 0 if free, else its cost
  | A modifier if is a decision named at its if keyword, after
  | the statement it guards, so its row is there too. The cost
  | call after it is no row.
  ) do
    source = <<~RUBY
      def price(item)
        return 0 if item.free?
        item.cost
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 11, 'if']], rows
  end

  test 'St3e08', %w(
  | Example: ship, writing an and chain, an if calling
  | send_off, then a value
  | A decision's row has as many paths as decision mode gives
  | the decision: an and of two operands 3, an if 2.
  | The call in the if's then, and the value, are no rows.
  ) do
    source = <<~RUBY
      def ship(order)
        ready = order.paid? && order.packed?
        if ready
          order.send_off
        end
        order
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.top, row.paths]
    end
    assert_equal [['&&', 3], ['if', 2]], rows
  end

  test 'St3e09', %w(
  | Example: fee, a write, four ifs, then a value
  | Its rows are its four ifs, the write and the value no rows.
  | Its size is the sum of its rows' paths, 2+2+2+2 = 8, the
  | paths its tests are to take.
  | Its ways are their product, 2*2*2*2 = 16, as its rows run
  | one after another, each path of one going on to each of the
  | next.
  ) do
    source = <<~RUBY
      def fee(user, order)
        total = order.total
        total -= 5 if user.member?
        total -= 10 if order.big?
        total += 3 if order.express?
        total += 1 if order.gift?
        total
      end
    RUBY
    paths = statements(source)['k.rb:1:0'].map(&:paths)
    assert_equal [8, 16], [
      PathCoverage::MethodStatements.size(paths),
      PathCoverage::CardWays.of(source, 'k.rb')['k.rb:1:0']
    ]
  end

  test 'St3e10', %w(
  | Example: ship, an if calling pack, then a value, its if's
  | then taken twice and its else never
  | A decision's row names its decision, so its taken is how many
  | of the decision's paths were taken, 1 of 2 here. The call and
  | the value are no rows.
  ) do
    source = <<~RUBY
      def ship(order)
        if order.paid?
          order.pack
        end
        order
      end
    RUBY
    rows = statements(source)['k.rb:1:0']
    paths = {
      'k.rb:2:2' => [
        { path: [true], count: 2 }, { path: [false], count: 0 }
      ]
    }
    assert_equal ['k.rb:2:2'], rows.map(&:decision)
    taken = PathCoverage::MethodStatements.taken(rows, paths)
    assert_equal [1], taken
  end

  test 'St3e11', %w(
  | Example: ship, sending each order inside an if's then,
  | rushed or not
  | The block is in the if's arm, so its ?: is a row once,
  | after the if, among the arm's rows: not again as a block of
  | the if's statement. The each call holding it is no row.
  ) do
    source = <<~RUBY
      def ship(orders, rush)
        if rush
          orders.each { |order| order.send_off(rush ? 1 : 2) }
        end
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 2, 'if'], [3, 46, '?:']], rows
  end

  test 'St3e12', %w(
  | Example: load, reading a file, rescuing a missing one, with
  | no else and no ensure
  | A def with a rescue has the rows of its statements before
  | the rescue, then its rescue's: here a ?: in each.
  ) do
    source = <<~RUBY
      def load(path, strict)
        text = File.read(path)
        text.empty? ? {} : JSON.parse(text)
      rescue Errno::ENOENT
        strict ? raise : {}
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[3, 14, '?:'], [5, 9, '?:']], rows
  end

  test 'St3e13', %w(
  | Example: record, writing an index, an attribute, an
  | instance variable, an op-write, then a &. attribute
  | No plain write is a row, though Ruby makes an index or
  | attribute write a call, eg of []=, as it is no decision.
  | A &. write is a decision, its call skipped when its receiver
  | is nil, so its row is the decision's: &., with 2 paths.
  ) do
    source = <<~RUBY
      def record(event, index, owner)
        event['index'] = index
        event.time = Time.now
        @count = index
        @count += 1
        owner&.last = event
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.top, row.paths]
    end
    assert_equal [['&.', 2]], rows
  end

  test 'St3e14', %w(
  | Example: a class with initialize and ship
  | Each def's name, by its decision, for its card's title.
  ) do
    source = <<~RUBY
      class Shop
        def initialize; end

        def ship(order) = order.pack
      end
    RUBY
    names = PathCoverage::MethodStatements.names(source, 'k.rb')
    expected = { 'k.rb:2:2' => :initialize, 'k.rb:4:2' => :ship }
    assert_equal expected, names
  end

  test 'St3e15', %w(
  | Example: ship, an if whose then returns, then a call
  | Each row that is no decision, here the return, is reached where
  | its statement starts, named by that place, so a call there
  | can count its runs. The if is a decision, its paths already
  | counted. The def is reached too, under its own decision, where
  | it is entered.
  ) do
    source = <<~RUBY
      def ship(order)
        if order.fragile?
          return order
        end
        order.pack
      end
    RUBY
    reaches = PathCoverage::MethodStatements.reaches(source, 'k.rb')
    assert_equal({ 'k.rb:1:0' => 18, 'k.rb:3:4' => 40 }, reaches)
  end

  test 'St3e16', %w(
  | Example: nope, an endless def of a raise
  | An endless def's body is one expression, so a reach call
  | put before it would end the def. Its row, the raise, is
  | reached by its byte range instead, for the call and it to be
  | wrapped together, as is the def's own reach, where it is
  | entered.
  ) do
    source = <<~RUBY
      def nope = raise('no')
    RUBY
    reaches = PathCoverage::MethodStatements.reaches(source, 'k.rb')
    expected = { 'k.rb:1:0' => 11...22, 'k.rb:1:11' => 11...22 }
    assert_equal expected, reaches
  end

  test 'St3e36', %w(
  | Example: ship, a def of one write; none, a def with an empty
  | body; one, an endless def
  | Each def is reached too, named by its own decision, so its card
  | can say how many times it was called: before its first
  | statement; before its end, for an empty body; and, for an
  | endless def, by its body's byte range, as its row is.
  ) do
    source = <<~RUBY
      def ship(a)
        x = 1
      end
      def none; end
      def one = 2
    RUBY
    reaches = PathCoverage::MethodStatements.reaches(source, 'k.rb')
    entries = reaches.slice('k.rb:1:0', 'k.rb:4:0', 'k.rb:5:0')
    expected = {
      'k.rb:1:0' => 14, 'k.rb:4:0' => 34, 'k.rb:5:0' => 48...49
    }
    assert_equal expected, entries
  end

  test 'St3e37', %w(
  | Example: pick, an if with an else, an if without, an unless
  | with an else, and a ?:
  | An if or unless with an else is if/else or unless/else, so
  | its row names both its arms; one without is if or unless; a
  | ?: is ?:, as always.
  ) do
    source = <<~RUBY
      def pick(a, b)
        if a then 1 else 2 end
        if b then 3 end
        unless a then 4 else 5 end
        a ? 6 : 7
      end
    RUBY
    tops = statements(source)['k.rb:1:0'].map(&:top)
    assert_equal ['if/else', 'if', 'unless/else', '?:'], tops
  end

  test 'St3e17', %w(
  | Example: ship, an if whose then returns, then a call, its
  | then taken twice, so the return reached twice
  | Each row is named by where it is.
  | A row that is no decision, the return, has 1 path, taken when
  | its statement was reached: 1 here, 0 had it not been.
  ) do
    source = <<~RUBY
      def ship(order)
        if order.fragile?
          return order
        end
        order.pack
      end
    RUBY
    rows = statements(source)['k.rb:1:0']
    paths = {
      'k.rb:2:2' => [
        { path: [true], count: 2 }, { path: [false], count: 0 }
      ]
    }
    assert_equal %w(k.rb:2:2 k.rb:3:4), rows.map(&:name)
    taken = [{ 'k.rb:3:4' => 2 }, {}].map do |reached|
      PathCoverage::MethodStatements.taken(rows, paths, reached)
    end
    assert_equal [[1, 1], [1, 0]], taken
  end

  test 'St3e18', %w(
  | Example: ship, an if whose then returns, then a call, its
  | then taken once, so the return reached
  | Its card's total is [taken, size]: [2, 3].
  | Without reaches, its return is not known, so it counts as
  | not taken: [1, 3], never more than it ran.
  ) do
    source = <<~RUBY
      def ship(order)
        if order.fragile?
          return order
        end
        order.pack
      end
    RUBY
    paths = {
      'k.rb:2:2' => [
        { path: [true], count: 1 }, { path: [false], count: 0 }
      ]
    }
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    context = PathCoverage::CardContext
    totals = [{ 'k.rb:3:4' => 1 }, nil].map do |reached|
      context.totals(source, 'k.rb', paths, reached, decisions)
    end
    expected = [{ 'k.rb:1:0' => [2, 3] }, { 'k.rb:1:0' => [1, 3] }]
    assert_equal expected, totals
  end

  test 'St3e19', %w(
  | Example: ship, logging with a call of its own, then raising
  | A call with no receiver that is no raise, eg log, ends no
  | path, so is no row; a raise does, so is one.
  ) do
    source = <<~RUBY
      def ship(order)
        log('shipped')
        raise 'empty' if order.nil?
        raise 'sent'
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[3, 16, 'if'], [4, 2, 'raise']], rows
  end

  test 'St3e20', %w(
  | Example: a class with initialize, on one line, and ship,
  | over three
  | Each def's last line, by its decision, where its card ends.
  ) do
    source = <<~RUBY
      class Shop
        def initialize; end

        def ship(order)
          order.pack
        end
      end
    RUBY
    lasts = PathCoverage::MethodStatements.lasts(source, 'k.rb')
    assert_equal({ 'k.rb:2:2' => 2, 'k.rb:4:2' => 6 }, lasts)
  end

  test 'St3e21', %w(
  | Example: install, a modifier if, a def of discount, then a
  | modifier if
  | Each modifier if is a row at its keyword.
  | A def inside a def is no row, as defining it decides
  | nothing.
  | It is not looked through, as its body runs only when
  | discount is called: discount's ?: is a row of discount's
  | card alone.
  ) do
    source = <<~RUBY
      def install(rates)
        return if rates.empty?
        def discount(total)
          total > 20 ? 20 : total
        end
        @tiered = true if rates.size > 1
      end
    RUBY
    rows = statements(source).transform_values do |each|
      each.map { [_1.line, _1.column, _1.top, _1.paths] }
    end
    expected = {
      'k.rb:1:0' => [[2, 9, 'if', 2], [6, 17, 'if', 2]],
      'k.rb:3:2' => [[4, 15, '?:', 2]]
    }
    assert_equal expected, rows
  end

  test 'St3e22', %w(
  | Example: capper, a write of a lambda holding a ?:, then a
  | value
  | A lambda's body runs only when it is called, so it is not
  | looked through, the write no row; its body's statements are
  | rows, as a block's are: here the ?:, with its 2 paths.
  ) do
    source = <<~RUBY
      def capper(most)
        cap = ->(total) { total > most ? most : total }
        cap
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top, row.paths]
    end
    assert_equal [[2, 33, '?:', 2]], rows
  end

  test 'St3e23', %w(
  | Example: fee, an if, its then a write, an elsif whose arm
  | is a write holding a modifier if, an else whose arm is a
  | write holding a ?:, then a value
  | The decisions in each arm's statements are rows too, flat,
  | after their if's row, in the order they are written; an
  | elsif is a decision of its own, so a row of its own, its top
  | elsif, as written. The writes and the value are no rows.
  | A modifier if's arm, and a ?:'s, are part of their
  | decision's row, so are no rows of their own.
  ) do
    source = <<~RUBY
      def fee(member, big)
        if member
          total = 5
        elsif big
          total = 10 if big.odd?
        else
          total = big ? 1 : 2
        end
        total
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top, row.paths]
    end
    expected = [
      [2, 2, 'if', 2], [4, 2, 'elsif', 2], [5, 15, 'if', 2],
      [7, 16, '?:', 2]
    ]
    assert_equal expected, rows
  end

  test 'St3e24', %w(
  | Example: remind, an if whose then holds only a comment,
  | its else a raise
  | An empty then has no rows; its else's raise is a row
  | after the if's.
  ) do
    source = <<~RUBY
      def remind(order)
        if order.paid?
          # nothing to do
        else
          raise 'unpaid'
        end
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 2, 'if/else'], [5, 4, 'raise']], rows
  end

  test 'St3e25', %w(
  | Example: ship, an unless raising, else returning, then a
  | modifier unless logging
  | An unless's arms' statements are rows too, after its
  | row, its then's before its else's, as an if's are.
  | A modifier unless's arm is part of its decision's row, so is
  | no row of its own.
  ) do
    source = <<~RUBY
      def ship(order)
        unless order.paid?
          raise 'unpaid'
        else
          return order if order.sent?
        end
        order.log unless order.quiet?
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    expected = [
      [2, 2, 'unless/else'], [3, 4, 'raise'], [5, 17, 'if'],
      [7, 12, 'unless']
    ]
    assert_equal expected, rows
  end

  test 'St3e26', %w(
  | Example: kind, a case whose two whens and else each return
  | a size
  | A case's arms' statements are rows too, after its row,
  | each when's in turn, then its else's.
  ) do
    source = <<~RUBY
      def kind(x)
        case x
        when 1, 2
          return :small
        when String
          return :text
        else
          return :other
        end
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    expected = [
      [2, 2, 'case'], [4, 4, 'return'], [6, 4, 'return'],
      [8, 4, 'return']
    ]
    assert_equal expected, rows
  end

  test 'St3e27', %w(
  | Example: labels, mapping items through an if; picks,
  | selecting items that are ok? && big?; and late, counting
  | the items that are late?
  | The decisions in a block's statements are rows too, after the
  | statement holding it, though they run once per item: the if
  | in labels, not its arms' values nor the map call.
  | A block method's call is a decision, its block's one
  | expression its leaf; that expression is a row too when it is
  | a decision, as the && in picks is, but not the call in late.
  ) do
    source = <<~RUBY
      def labels(items)
        items.map do |item|
          if item[:sale]
            'sale'
          else
            'full'
          end
        end
      end

      def picks(items)
        items.select { |i| i.ok? && i.big? }
      end

      def late(items)
        items.count { |i| i.late? }
      end
    RUBY
    rows = statements(source).transform_values do |each|
      each.map { [_1.line, _1.column, _1.top] }
    end
    expected = {
      'k.rb:1:0' => [[3, 4, 'if/else']],
      'k.rb:11:0' => [[12, 8, 'select'], [12, 21, '&&']],
      'k.rb:15:0' => [[16, 8, 'count']]
    }
    assert_equal expected, rows
  end

  test 'St3e28', %w(
  | Example: load, reading a file, with two rescues, an else
  | and an ensure
  | Each rescue's statements are rows too, as a rescue runs
  | when its exception is raised; then the else's, run when
  | none is; then the ensure's, run either way: flat, in the
  | order they are written.
  ) do
    source = <<~RUBY
      def load(path)
        text = File.read(path)
      rescue Errno::ENOENT
        return ''
      rescue IOError
        return nil
      else
        return text.strip
      ensure
        log(path) if path
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    expected = [
      [4, 2, 'return'], [6, 2, 'return'], [8, 2, 'return'],
      [10, 12, 'if']
    ]
    assert_equal expected, rows
  end

  test 'St3e29', %w(
  | Example: fetch, writing the value of a begin whose rescue
  | retries later if it can, then a value
  | A begin's statements, and its rescue's, are rows too,
  | after the statement holding it, as a block's are.
  | So the write is not looked through into the begin: the
  | modifier if is a row once, in the rescue's place.
  ) do
    source = <<~RUBY
      def fetch(url, retries)
        body = begin
          get(url)
        rescue Timeout::Error
          retry_later(url) if retries.positive?
        end
        body
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[5, 21, 'if']], rows
  end

  test 'St3e30', %w(
  | Example: every Ruby file of the gem's lib and test, and of
  | its demo's source
  | Every decision decision mode finds in a file is on some card,
  | a row of a def that holds it, or is outside every def,
  | where its own line opens its tree: no decision is on no card.
  ) do
    root = File.expand_path('..', __dir__)
    globs = %w(lib/**/*.rb test/*.rb demo/source/*.rb)
    files = globs.flat_map { Dir.glob(_1, base: root) }.sort
    unseen = files.flat_map do |file|
      decisions = unseen_decisions(File.read("#{root}/#{file}"))
      decisions.map { "#{file} #{_1}" }
    end
    assert_equal [], unseen
  end

  test 'St3e31', %w(
  | Example: label, returning a ?:'s value if node, then a &.
  | call on a ?:'s value
  | A decision inside another decision that is a decision of
  | its own, as a modifier if's arm and a &. receiver are, is a
  | row too,
  | the decision and those inside it in the order they are named,
  | left to right: the ?: before the modifier if it is in.
  ) do
    source = <<~RUBY
      def label(node, kind)
        return kind ? 'a' : 'b' if node
        (node.ok? ? node : kind)&.name
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    expected = [
      [2, 14, '?:'], [2, 26, 'if'], [3, 2, '&.'], [3, 12, '?:']
    ]
    assert_equal expected, rows
  end

  test 'St3e35', %w(
  | Example: ship, a ?: whose predicate is a || b
  | The || is a decision of its own inside the ?:, named where it
  | starts, before the ?:'s ?, so its row comes first.
  ) do
    source = <<~RUBY
      def ship(a, b)
        a || b ? 0 : 7
      end
    RUBY
    rows = statements(source)['k.rb:1:0'].map do |row|
      [row.line, row.column, row.top]
    end
    assert_equal [[2, 2, '||'], [2, 9, '?:']], rows
  end

  test 'St3e32', %w(
  | Example: memo, @m ||= a && b, in a run ignoring ||=
  | A card's rows are of the decisions the run has, as given: here
  | the ||= is no decision, so the write is looked through, and its
  | row is the && inside it.
  ) do
    source = <<~RUBY
      def memo(a, b)
        @m ||= a && b
      end
    RUBY
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb',
                                                 ['||='])
    rows = PathCoverage::MethodStatements.of(source, 'k.rb',
                                             decisions)
    tops = rows['k.rb:1:0'].map { [_1.line, _1.column, _1.top] }
    assert_equal [[2, 9, '&&']], tops
  end

  test 'St3e33', %w(
  | Example: rate, a ?: at the top level, its then taken, and
  | fee, a def of a ?:
  | The decisions on no card, those outside every def, total
  | [taken, possible] of their own: rate's 1 of 2. fee's ?:
  | is on fee's card, so is not among them.
  ) do
    source = <<~RUBY
      RATE = ENV.key?('RATE') ? 2 : 1
      def fee(big) = big ? 10 : 5
    RUBY
    taken = lambda do |counts|
      [{ path: [true], count: counts[0] },
       { path: [false], count: counts[1] }]
    end
    paths = { 'k.rb:1:24' => taken.call([3, 0]),
              'k.rb:2:19' => taken.call([1, 1]) }
    statements = PathCoverage::MethodStatements
    assert_equal [1, 2], statements.top_level(source, 'k.rb', paths)
  end

  test 'St3e34', %w(
  | Example: fee, two ?:s on one top-level line, an elsif at
  | the top level, and big?, a def of an &&
  | Each decision on no card, outside every def, is a row of its
  | own, for its line's card: where it is named, its operator,
  | an elsif's elsif, and its paths, in the order written.
  | big?'s && is on big?'s card, so is not among them.
  ) do
    source = <<~RUBY
      FEE = (ENV['BIG'] ? 10 : 0) + (ENV['VIP'] ? 5 : 0)
      if FEE > 10
        warn 'big'
      elsif FEE > 5
        warn 'some'
      end
      def big?(a, b) = a && b
    RUBY
    rows = PathCoverage::MethodStatements.top_rows(source, 'k.rb')
    actual = rows.map do |row|
      [row.line, row.column, row.top, row.paths, row.decision]
    end
    expected = [
      [1, 18, '?:', 2, 'k.rb:1:18'], [1, 42, '?:', 2, 'k.rb:1:42'],
      [2, 0, 'if', 2, 'k.rb:2:0'], [4, 0, 'elsif', 2, 'k.rb:4:0']
    ]
    assert_equal expected, actual
  end

  private

  # { def decision => its statements' rows } for source, as if it
  # were k.rb.
  def statements(source)
    PathCoverage::MethodStatements.of(source, 'k.rb')
  end

  # The decisions decision mode finds in source that are on no
  # card: those on a line inside a def, from its def line to its
  # last, but no row's decision.
  def unseen_decisions(source)
    rows = statements(source).values.flatten.filter_map(&:decision)
    lasts = PathCoverage::MethodStatements.lasts(source, 'k.rb')
    lines = lasts.flat_map do |decision, last|
      [*line_of(decision)..last]
    end
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb').keys
    by_line = decisions.group_by { line_of(_1) }
    lines.uniq.flat_map { by_line.fetch(_1, []) } - rows
  end

  # The line of decision, eg 4 for "k.rb:4:2".
  def line_of(decision)
    Integer(decision.split(':')[-2])
  end
end
