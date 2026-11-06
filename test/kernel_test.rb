require_relative 'test_helper'
require 'path_coverage/kernel'
require 'json'
require 'rexml/document'

class KernelTest < TidTest
  # Its tests swap the configuration of the one global load
  # hook, and capture $stdout.
  serial!

  test '6rTS10', %w(
  | PathCoverage.record, the call rewritten code makes,
  | returns the operand's value and counts it
  | in the one shared recorder
  ) do
    site = 'kernel_test.rb:6rTS10:0' # used by no other test
    kata = { 'id' => 'Kp9sA2' }
    assert_same kata, PathCoverage.record(site, 0, kata)

    expected = { truthy: 1, falsy: 0 }
    actual = PathCoverage.recorder.counts[[site, 0]]
    assert_equal expected, actual
  end

  test '6rTS20', %w(
  | once started with a root and a cover glob,
  | a file matching the glob has its && operands recorded
  | when they run, at sites named relative to the root
  ) do |t|
    t.write(<<~RUBY, 'kata.rb')
      module Kata
        def self.ok?(id) = !id.empty?
        def self.kata?(id) = ok?(id) && id.start_with?('N')
      end
    RUBY
    t.start # this test checks the recording only
    t.load('kata.rb')::Kata.kata?('N1')
    site = 'kata.rb:3:23'
    expected = {
      [site, 0] => { truthy: 1, falsy: 0 },
      [site, 1] => { truthy: 1, falsy: 0 }
    }
    assert_equal expected, PathCoverage.recorder.counts
  end

  test '6rTS30', %w(
  | a file outside the root is left for Ruby
  | to load as normal, uninstrumented
  ) do |t|
    covered = "#{t.dir}/covered"
    FileUtils.mkdir_p(covered)
    t.write("def kata?(id) = ok?(id) && new?(id)\n", 'other/kata.rb')
    path = "#{t.dir}/other/kata.rb"
    config = PathCoverage::Configuration.new do
      root covered
      cover '*.rb'
    end
    assert_nil PathCoverage.instrumented(path, config)
  end

  test '6rTS40', %w(
  | the report made as the process exits prints the gaps
  | and writes every operand count as JSON to coverage_dir
  ) do |t|
    t.write(<<~RUBY, 'group.rb')
      module Group
        def self.ok?(id) = !id.empty?
        def self.group?(id) = ok?(id) && id.size == 6
      end
    RUBY
    t.start
    t.load('group.rb')::Group.group?('Kp9sA2')
    never = 'group.rb:3:24 path never taken: `ok?(id)`'
    expected = [
      "#{never} true, `id.size == 6` false",
      "#{never} false"
    ].join("\n")
    assert_output("#{expected}\n") { t.report }

    json = t.json
    expected = {
      'group.rb:3:24' => [
        { 'truthy' => 1, 'falsy' => 0 },
        { 'truthy' => 1, 'falsy' => 0 }
      ]
    }
    assert_equal expected, json['sites']
  end

  test '6rTS42', %w(
  | a ternary's path is recorded as it runs, so one whose
  | predicate was only ever true lists its false path as a gap
  ) do |t|
    t.write(<<~RUBY, 'fee.rb')
      module Fee
        def self.fee(member) = member ? 5 : 7
      end
    RUBY
    t.start
    t.load('fee.rb')::Fee.fee(true)
    expected = "fee.rb:2:32 path never taken: `member` false\n"
    assert_output(expected) { t.report }
  end

  test '6rTS43', %w(
  | Example: user[:member] || user[:vip] ? 5 : 7, called once
  | The ?: is a site of one leaf, its predicate, and the || a
  | site of its own; each evaluation's path through each is
  | recorded, and each path never taken printed as a gap.
  | The JSON report has every path's count, and each leaf's
  | span.
  | Its totals give decisions as [taken, possible]: [2, 5],
  | and methods the same, fee's card having the ?: and || rows.
  ) do |t|
    t.write(<<~RUBY, 'fee.rb')
      module Fee
        def self.fee(user) = user[:member] || user[:vip] ? 5 : 7
      end
    RUBY
    t.start
    t.load('fee.rb')::Fee.fee({ member: true })
    either = '`user[:member] || user[:vip]`'
    never = 'fee.rb:2:23 path never taken: `user[:member]` false'
    expected = [
      "fee.rb:2:51 path never taken: #{either} false",
      "#{never}, `user[:vip]` true",
      "#{never}, `user[:vip]` false"
    ].join("\n")
    assert_output("#{expected}\n") { t.report }

    json = t.json
    expected = {
      'fee.rb:2:51' => {
        'leaves' => [%w(2:23 2:50)],
        'taken' => [
          { 'path' => [true], 'count' => 1 },
          { 'path' => [false], 'count' => 0 }
        ]
      },
      'fee.rb:2:23' => {
        'leaves' => [%w(2:23 2:36), %w(2:40 2:50)],
        'taken' => [
          { 'path' => [true, nil], 'count' => 1 },
          { 'path' => [false, true], 'count' => 0 },
          { 'path' => [false, false], 'count' => 0 }
        ]
      }
    }
    assert_equal expected, json['paths']
    totals = { 'decisions' => [2, 5], 'methods' => [2, 5] }
    assert_equal totals, json['totals']
  end

  test '6rTS45', %w(
  | a file loaded during the run is not read again for the
  | exit report: the sites parsed as it loaded are reused,
  | so each covered file is read and parsed at most once
  ) do |t|
    t.write(<<~RUBY, 'team.rb')
      module Team
        def self.ok?(id) = !id.empty?
        def self.team?(id) = ok?(id) && id.size == 6
      end
    RUBY
    t.start
    t.load('team.rb')::Team.team?('Kp9sA2')
    # A re-read of the file now would find no &&.
    t.write("module Team; end\n", 'team.rb')
    never = 'team.rb:3:23 path never taken: `ok?(id)`'
    expected = [
      "#{never} true, `id.size == 6` false",
      "#{never} false"
    ].join("\n")
    assert_output("#{expected}\n") { t.report }
  end

  test '6rTS47', %w(
  | a covered file the run never loads is parsed for the
  | exit report, so each of its && sites is reported
  | as never reached
  ) do |t|
    t.write(<<~RUBY, 'squad.rb')
      module Squad
        def self.ok?(id) = !id.empty?
        def self.squad?(id) = ok?(id) && id.size == 6
      end
    RUBY
    t.start
    assert_output("squad.rb:3:24 never reached\n") { t.report }
  end

  test '6rTS4h', %w(
  | Example: group 'Models', 'models/*.rb', of covered files
  | models/crew.rb and lib/zip.rb
  | The source report's Models group lists models/crew.rb alone.
  | The JSON report's totals have each group's own too: Models
  | took none of crew?'s 3 paths, within its decision or its
  | method.
  ) do |t|
    t.write("def crew?(a, b) = a && b\n", 'models/crew.rb')
    t.write("def zip?(a, b) = a || b\n", 'lib/zip.rb')
    exit_report = nil
    on_exit = ->(&block) { exit_report = block }
    PathCoverage.start(on_exit:) do
      root t.dir
      cover '**/*.rb'
      coverage_dir t.dir
      report
      group 'Models', 'models/*.rb'
    end
    exit_report.call

    written = File.read("#{t.dir}/path_coverage.source.json")
    models = JSON.parse(written)['groups']['Models']
    assert_equal ['models/crew.rb'], models
    json = t.json
    groups = {
      'Models' => { 'decisions' => [0, 3], 'methods' => [0, 3] }
    }
    assert_equal groups, json['totals']['groups']
  end

  test '6rTS4n', %w(
  | Example: group 'Models', 'models/*.rb', and lib/zip.rb the
  | only covered file
  | No covered file is in the Models group.
  | The JSON report's Models totals are [0, 0], within
  | decisions and within methods.
  ) do |t|
    t.write("def zip?(a, b) = a || b\n", 'lib/zip.rb')
    exit_report = nil
    on_exit = ->(&block) { exit_report = block }
    PathCoverage.start(on_exit:) do
      root t.dir
      cover '**/*.rb'
      coverage_dir t.dir
      report
      group 'Models', 'models/*.rb'
    end
    exit_report.call

    json = t.json
    groups = {
      'Models' => { 'decisions' => [0, 0], 'methods' => [0, 0] }
    }
    assert_equal groups, json['totals']['groups']
  end

  test '6rTS4p', %w(
  | Example: items_of, an if then a ternary, called with nil,
  | { basket: [1] }, [2] and { basket: 'x' }
  | The ternary's predicate is its decision, not its value.
  | So the four calls take all four paths: [F,F], [T,T],
  | [F,T] and [T,F].
  | And each site took every path too.
  | So there are no gaps to print.
  ) do |t|
    t.write(<<~RUBY, 'items.rb')
      module Items
        def self.items_of(order)
          order = order[:basket] if order.is_a?(Hash)
          order.is_a?(Array) ? order : []
        end
      end
    RUBY
    t.start
    items_module = t.load('items.rb')::Items
    orders = [nil, { basket: [1] }, [2], { basket: 'x' }]
    items = orders.map { |order| items_module.items_of(order) }
    assert_equal [[], [1], [2], []], items
    assert_output('', '') { t.report }
  end

  test '6rTS4t', %w(
  | Example: store[key] ||= key.upcase and name &&= name.strip,
  | each called once skipping its right side and once not
  | Each is a site, its one leaf its target.
  | The target is never read again: its outcome follows from
  | whether the right side ran.
  | ||= runs it when the target is false, &&= when true.
  | Both paths of each were taken, so there are no gaps.
  | The values are those of the uninstrumented code.
  ) do |t|
    t.write(<<~RUBY, 'cache_writes.rb')
      module Cache
        def self.fetch(store, key)
          store[key] ||= key.upcase
        end
        def self.trim(name)
          name &&= name.strip
          name
        end
      end
    RUBY
    t.start
    cache = t.load('cache_writes.rb')::Cache
    fetched = [{}, { 'a' => 'B' }].map do |store|
      cache.fetch(store, 'a')
    end
    trimmed = [' x ', nil].map { |name| cache.trim(name) }
    assert_equal [%w(A B), ['x', nil]], [fetched, trimmed]
    assert_output('', '') { t.report }

    json = t.json
    taken = %w(cache_writes.rb:3:4 cache_writes.rb:6:4).to_h do |site|
      [site, json['paths'][site]['taken']]
    end
    both = [{ 'path' => [true], 'count' => 1 },
            { 'path' => [false], 'count' => 1 }]
    expected = {
      'cache_writes.rb:3:4' => both, 'cache_writes.rb:6:4' => both
    }
    assert_equal expected, taken
  end

  test '6rTS4u', %w(
  | Example: store[:size] ||= 0, called only with an empty store
  | Its target was false each time, so its right side ran.
  | So the path with its target true is a gap.
  ) do |t|
    t.write(<<~RUBY, 'fill_writes.rb')
      module Fill
        def self.fill(store)
          store[:size] ||= 0
        end
      end
    RUBY
    t.start
    assert_equal 0, t.load('fill_writes.rb')::Fill.fill({})
    gap = "fill_writes.rb:3:4 path never taken: `store[:size]` true\n"
    assert_output(gap, '') { t.report }
  end

  test '6rTS4v', %w(
  | Example: ||= on a constant, an instance variable with a command
  | call on its right, an attribute, a class variable and a global
  | Each is a site, and the rewritten code still loads and runs.
  | clock and grow, called twice, take both paths of each.
  | LIMIT ||= 6 runs once, as the module loads, so its target
  | true is the one gap.
  ) do |t|
    t.write(<<~RUBY, 'memo_writes.rb')
      module Memo
        LIMIT ||= 6
        @@count = nil
        class << self
          attr_accessor :size
        end
        def self.clock
          @clock ||= Time.at 0
        end
        def self.grow(n)
          self.size ||= n
          @@count ||= 0
          $memo6rTS4v ||= n
          [size, @@count, $memo6rTS4v]
        end
      end
    RUBY
    t.start
    memo = t.load('memo_writes.rb')::Memo
    clocks = 2.times.map { memo.clock }
    grown = [3, 5].map { |n| memo.grow(n) }
    assert_equal [[Time.at(0)] * 2, [[3, 0, 3]] * 2], [clocks, grown]
    gap = "memo_writes.rb:2:2 path never taken: `LIMIT` true\n"
    assert_output(gap, '') { t.report }

    json = t.json
    sites = %w(2:2 8:4 11:4 12:4 13:4).map { "memo_writes.rb:#{_1}" }
    counts = sites.to_h do |site|
      [site, json['paths'][site]['taken'].map { _1['count'] }]
    end
    expected = sites.to_h { |site| [site, [1, 1]] }
    expected['memo_writes.rb:2:2'] = [0, 1]
    assert_equal expected, counts
  end

  test '6rTS4w', %w(
  | Example: @port ||= Integer(text) rescue 80, a rescue modifier
  | on the right of ||=, called with 'x' then '8080'
  | The rewritten code still loads, the modifier needing
  | parentheses to be an argument.
  | It returns what the same code, uninstrumented, returns.
  | 'x' runs the right side, which rescues to 80; '8080' finds
  | @port set and skips it. So both paths are taken: no gaps.
  ) do |t|
    source = lambda do |name|
      <<~RUBY
        module #{name}
          def self.port(text)
            @port ||= Integer(text) rescue 80
          end
        end
      RUBY
    end
    t.write(source.call('Port'), 'port_writes.rb')
    t.start
    port = t.load('port_writes.rb')::Port
    eval(source.call('Plain6rTS4w')) # rubocop:disable Security/Eval
    texts = %w(x 8080)
    plain = texts.map { |text| Plain6rTS4w.port(text) }
    actual = texts.map { |text| port.port(text) }
    assert_equal [[80, 80], plain], [actual, actual]
    assert_output('', '') { t.report }
  end

  test '6rTS4x', %w(
  | Example: user&.account&.owner, called with no user, a user
  | with no account, and a user whose account has an owner
  | The chain is one site, named where it starts.
  | Its leaves are its receivers, user and user&.account.
  | Each is nil or not nil, as &. calls on anything not nil,
  | false included.
  | A nil receiver skips the rest of the chain, so the leaves
  | after it are not reached.
  | All three paths are taken, so there are no gaps.
  ) do |t|
    t.write(<<~RUBY, 'safe_owner.rb')
      module Owner
        User = Struct.new(:account)
        def self.owner(user)
          user&.account&.owner
        end
        Account = Struct.new(:owner)
      end
    RUBY
    t.start
    owner = t.load('safe_owner.rb')::Owner
    user = owner::User
    users = [nil, user.new(nil), user.new(owner::Account.new('kim'))]
    owners = users.map { |each| owner.owner(each) }
    assert_equal [nil, nil, 'kim'], owners
    assert_output('', '') { t.report }

    json = t.json
    expected = [
      { 'path' => ['not nil', 'not nil'], 'count' => 1 },
      { 'path' => ['not nil', 'nil'], 'count' => 1 },
      { 'path' => ['nil', nil], 'count' => 1 }
    ]
    assert_equal expected, json['paths']['safe_owner.rb:4:4']['taken']
  end

  test '6rTS4y', %w(
  | Example: user&.account&.owner, called only with a user whose
  | account has an owner
  | Each path with a nil receiver is a gap, naming each
  | receiver it reaches, nil or not nil.
  ) do |t|
    t.write(<<~RUBY, 'safe_gaps.rb')
      module Gaps
        User = Struct.new(:account)
        def self.owner(user)
          user&.account&.owner
        end
        Account = Struct.new(:owner)
      end
    RUBY
    t.start
    safe = t.load('safe_gaps.rb')::Gaps
    account = safe::Account.new('kim')
    assert_equal 'kim', safe.owner(safe::User.new(account))
    never = 'safe_gaps.rb:4:4 path never taken:'
    gaps = [
      "#{never} `user` not nil, `user&.account` nil",
      "#{never} `user` nil"
    ].map { "#{_1}\n" }.join
    assert_output(gaps, '') { t.report }
  end

  test '6rTS4z', %w(
  | Example: ok && user&.admin?, called with ok false, then ok
  | true and no user, a user not an admin, and an admin
  | The chain folds into the && site, as one expression.
  | Its leaves follow ok's: user, nil or not nil, then the
  | chain's value, true or false, when every receiver was not
  | nil.
  | So the four calls take the site's four paths.
  | The card shows the chain's rows under its &. as user then
  | admin?, so the &. is not shown twice.
  | user's cells are a disc for not nil and an empty set for nil.
  | Each is titled not nil or nil, for its hover text.
  ) do |t|
    t.write(<<~RUBY, 'safe_admin.rb')
      module Admin
        User = Struct.new(:role) do
          def admin? = role == :admin
        end
        def self.admin?(ok, user)
          ok && user&.admin?
        end
      end
    RUBY
    t.start { report }
    admin = t.load('safe_admin.rb')::Admin
    user = admin::User
    calls = [[false, nil], [true, nil], [true, user.new(:dev)],
             [true, user.new(:admin)]]
    answers = calls.map { |ok, each| admin.admin?(ok, each) }
    assert_equal [false, nil, false, true], answers
    assert_output('', '') { t.report }

    json = t.json
    taken = json['paths']['safe_admin.rb:6:4']['taken']
    assert_equal([1, 1, 1, 1], taken.map { _1['count'] })
    rows = of_kind(fold_at(t, 'safe_admin.rb:6'), 'operand')
    texts = rows.map { shown(_1).first }
    assert_equal ['ok', 'user', 'admin?'], texts
    assert_equal ['user', 'present', 'present', 'absent', ''],
                 shown(rows[1])
    titles = rows[1]['cells'].map { |_, _, hover| hover }
    assert_equal ['not nil', 'not nil', 'nil', nil], titles
  end

  test '6rTS5a', %w(
  | Example: if user&.admin?, called with no user, a user not an
  | admin, and an admin
  | The chain folds into the if site as its predicate.
  | So the three calls take its three paths: user nil, and
  | user not nil with admin? true or false.
  ) do |t|
    t.write(<<~RUBY, 'safe_label.rb')
      module Label
        User = Struct.new(:role) do
          def admin? = role == :admin
        end
        def self.label(user)
          if user&.admin?
            :admin
          else
            :user
          end
        end
      end
    RUBY
    t.start
    label = t.load('safe_label.rb')::Label
    user = label::User
    users = [nil, user.new(:dev), user.new(:admin)]
    labels = users.map { |each| label.label(each) }
    assert_equal %i[user user admin], labels
    assert_output('', '') { t.report }

    json = t.json
    taken = json['paths']['safe_label.rb:6:4']['taken']
    assert_equal([1, 1, 1], taken.map { _1['count'] })
  end

  test '6rTS5b', %w(
  | Example: box&.size ||= 3, called with no box, a box with no
  | size and a box of size 5
  | With no box, the whole write is skipped: its right side
  | does not run, yet the target was not found set either.
  | So the write is no site, rather than one reporting its
  | target set when it was never looked at.
  ) do |t|
    t.write(<<~RUBY, 'safe_write.rb')
      module Fill
        Box = Struct.new(:size)
        def self.fill(box)
          box&.size ||= 3
        end
      end
    RUBY
    t.start
    fill = t.load('safe_write.rb')::Fill
    box = fill::Box
    boxes = [nil, box.new(nil), box.new(5)]
    sizes = boxes.map { fill.fill(_1) }
    assert_equal [nil, 3, 5], sizes
    assert_output('', '') { t.report }

    json = t.json
    assert_equal({}, json.fetch('paths', {}))
  end

  test '6rTS5d', %w(
  | Example: ids.any? { |id| id.odd? }, standing alone, called with
  | no ids, one odd, one even, an even then an odd, and two even
  | It is a site of its own, being no part of a larger expression.
  | The five calls take its five paths, so there are no gaps.
  ) do |t|
    t.write(<<~RUBY, 'found_odd.rb')
      module Found
        def self.found?(ids)
          ids.any? { |id| id.odd? }
        end
      end
    RUBY
    t.start
    odd = t.load('found_odd.rb')::Found
    calls = [[], [1], [2], [2, 3], [2, 4]]
    found = calls.map { |ids| odd.found?(ids) }
    assert_equal [false, true, false, true, false], found
    assert_output('', '') { t.report }
  end

  test '6rTS5e', %w(
  | Example: ids.select { |id| id.odd? }.any? &&
  | ids.all? { |id| id > 0 }
  | The select sits inside the leaf ids.select { ... }.any?, and
  | folds into the && site: its fold shows the select's rows,
  | headed select {, then the leaf's own row, }.any?, so they
  | read as the code does.
  | The all? is the &&'s operand itself, so it is a site of its
  | own, the &&'s fold showing it as one leaf.
  ) do |t|
    t.write(<<~RUBY, 'both_html.rb')
      module Both
        def self.both?(ids)
          ids.select { |id| id.odd? }.any? && ids.all? { |id| id > 0 }
        end
      end
    RUBY
    t.start { report }
    both = t.load('both_html.rb')::Both
    answers = [[1], [2], [1, -1]].map { |ids| both.both?(ids) }
    assert_equal [true, false, false], answers
    assert_output('', '') { t.report }

    rows = fold_at(t, 'both_html.rb:3')
    operators = rows - of_kind(rows, 'operand')
    names = operators.map { shown(_1).first }
    assert_equal ['&&', 'select {'], names
    texts = of_kind(rows, 'operand').map { shown(_1).first }
    all = 'ids.all? { |id| id > 0 }'
    assert_equal ['ids', 'id.odd?', '}.any?', all], texts
  end

  test '6rTS5c', %w(
  | Example: lookup(id)&.rename 'kim', a chain whose first call
  | has no receiver and whose last is a command call, called
  | with an id found and one not
  | The rewritten code still loads, the command parenthesised.
  | Both paths are taken: lookup(id) nil, and not nil.
  ) do |t|
    t.write(<<~RUBY, 'safe_rename.rb')
      module Rename
        User = Struct.new(:name) do
          def rename(name)
            self.name = name
          end
        end
        USERS = { 1 => User.new('al') }.freeze
        def self.lookup(id) = USERS[id]
        def self.rename(id)
          lookup(id)&.rename 'kim'
        end
      end
    RUBY
    t.start
    rename = t.load('safe_rename.rb')::Rename
    names = [2, 1].map { |id| rename.rename(id) }
    assert_equal [nil, 'kim'], names
    assert_output('', '') { t.report }

    json = t.json
    taken = json['paths']['safe_rename.rb:10:4']['taken']
    assert_equal([1, 1], taken.map { _1['count'] })
  end

  test '6rTS49', %w(
  | a coverage_dir that does not exist yet is created,
  | parents and all, before the exit report writes into it
  ) do |t|
    t.write(<<~RUBY, 'pair.rb')
      module Pair
        def self.ok?(id) = !id.empty?
        def self.pair?(id) = ok?(id) && id.size == 6
      end
    RUBY
    out = "#{t.dir}/reports/condition"
    exit_report = nil
    on_exit = ->(&block) { exit_report = block }
    PathCoverage.start(on_exit:) do
      root t.dir
      cover '*.rb'
      coverage_dir out
      report
    end
    exit_report.call

    assert File.file?("#{out}/path_coverage.json")
  end

  test '6rTS44', %w(
  | the exit report writes the source report beside the JSON
  | report: each covered file's lines and its sites
  ) do |t|
    t.write(<<~RUBY, 'pair.rb')
      module Pair
        def self.ok?(id) = !id.empty?
        def self.pair?(id) = ok?(id) && id.size == 6
      end
    RUBY
    exit_report = nil
    on_exit = ->(&block) { exit_report = block }
    PathCoverage.start(on_exit:) do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      report
    end
    exit_report.call

    written = File.read("#{t.dir}/path_coverage.source.json")
    report = JSON.parse(written)
    file = report['files'].fetch('pair.rb')
    assert_equal 4, file['lines'].size
    assert_equal ['pair.rb:3:23'], file['sites'].keys
    assert_equal '&&', report['labels']['&&']['text']
  end

  test '6rTS4b', %w(
  | starting from the environment covers each of its
  | comma-separated globs under its root, writing the JSON
  | report to its dir and POSTing it to its collector
  ) do |t|
    t.write("def kata?(id) = id\n", 'source/kata.rb')
    t.write("def team?(id) = id\n", 'lib/team.rb')
    env = {
      'PATH_COVERAGE_ROOT' => t.dir,
      'PATH_COVERAGE_COVER' => 'source/*.rb,lib/*.rb',
      'PATH_COVERAGE_DIR' => "#{t.dir}/condition",
      'PATH_COVERAGE_COLLECTOR' => 'http://10.0.0.7:4570/runs'
    }
    on_exit = ->(&_report) {} # this test checks the settings only
    PathCoverage.start_from_env(env, on_exit:)

    config = PathCoverage.config
    actual = [
      config.files, config.json_path,
      config.collector_url, config.reporters
    ]
    expected = [
      ["#{t.dir}/lib/team.rb", "#{t.dir}/source/kata.rb"],
      "#{t.dir}/condition/path_coverage.json",
      'http://10.0.0.7:4570/runs', [:post]
    ]
    assert_equal expected, actual
  end

  test '6rTS4g', %w(
  | Example: PATH_COVERAGE_SKIP=source/vendor/**/*.rb,lib/gen.rb
  | Starting from the environment skips each of its
  | comma-separated skip globs.
  | So only source/kata.rb is covered of the three files.
  ) do |t|
    t.write("def kata?(id) = id\n", 'source/kata.rb')
    t.write("def zip?(id) = id\n", 'source/vendor/zip.rb')
    t.write("def gen?(id) = id\n", 'lib/gen.rb')
    env = {
      'PATH_COVERAGE_ROOT' => t.dir,
      'PATH_COVERAGE_COVER' => 'source/**/*.rb,lib/*.rb',
      'PATH_COVERAGE_SKIP' => 'source/vendor/**/*.rb,lib/gen.rb',
      'PATH_COVERAGE_DIR' => "#{t.dir}/condition",
      'PATH_COVERAGE_COLLECTOR' => 'http://10.0.0.7:4570/runs'
    }
    on_exit = ->(&_report) {} # this test checks the settings only
    PathCoverage.start_from_env(env, on_exit:)
    kata = "#{t.dir}/source/kata.rb"
    assert_equal [kata], PathCoverage.config.files
  end

  test '6rTS41', %w(
  | Example: fee with if member ... end and if big ... end
  | measure :decisions, :methods is chosen.
  | fee is called once, with member true and big false.
  | The exit report prints each if's path never taken, eg
  | `member` false.
  | The JSON report's totals are [taken, possible]:
  | decisions [2, 4], one path of each if's two.
  | methods [2, 4] too, fee's card having just its two ifs as
  | rows, its writes and value none.
  ) do |t|
    t.write(<<~RUBY, 'fee.rb')
      module Fee
        def self.fee(member, big)
          total = 100
          if member
            total -= 5
          end
          if big
            total -= 10
          end
          total
        end
      end
    RUBY
    t.start
    assert_equal 95, t.load('fee.rb')::Fee.fee(true, false)
    expected = [
      'fee.rb:4:4 path never taken: `member` false',
      'fee.rb:7:4 path never taken: `big` true'
    ].join("\n")
    assert_output("#{expected}\n") { t.report }
    totals = { 'decisions' => [2, 4], 'methods' => [2, 4] }
    assert_equal totals, t.json['totals']
  end

  test '6rTS4c', %w(
  | Example: case x when 1, 2 ... when String ... else ... end
  | kind is called with 2 and with :k.
  | The covered case still picks :small and :other.
  | The exit report prints each path its patterns never took.
  | Eg `1` true, as 1 was never passed.
  ) do |t|
    t.write(<<~RUBY, 'kind.rb')
      module Kind
        def self.kind(x)
          case x
          when 1, 2 then :small
          when String then :text
          else :other
          end
        end
      end
    RUBY
    t.start
    kind = t.load('kind.rb')::Kind
    actual = [kind.kind(2), kind.kind(:k)]
    assert_equal %i[small other], actual
    never = 'kind.rb:3:4 path never taken:'
    expected = [
      "#{never} `1` true",
      "#{never} `1` false, `2` false, `String` true"
    ].join("\n")
    assert_output("#{expected}\n") { t.report }
  end

  test '6rTS4d', %w(
  | Example: if ids.any? { |id| id.start_with?('L') && id.size > 1 }
  | There are three sites: the if, its predicate wholly the any?,
  | the any?, a site of its own, and the && in the block, a new
  | scope.
  | led? is called with [], ['Lx'], and ['ab', 'cd'].
  | It still returns :not, :led, :not.
  | The exit report prints the paths each site never took.
  | Eg the any? never had `ids` 1 item with the block false; the
  | if took both its arms.
  ) do |t|
    t.write(<<~RUBY, 'led.rb')
      module Team
        def self.led?(ids)
          if ids.any? { |id| id.start_with?('L') && id.size > 1 }
            :led
          else
            :not
          end
        end
      end
    RUBY
    t.start
    team = t.load('led.rb')::Team
    led = [[], ['Lx'], %w(ab cd)].map { |ids| team.led?(ids) }
    assert_equal %i[not led not], led
    block = "`id.start_with?('L') && id.size > 1`"
    expected = [
      "led.rb:3:11 path never taken: `ids` 1 item, #{block} false",
      "led.rb:3:11 path never taken: `ids` 2+ items, #{block} true",
      'led.rb:3:23 path never taken: ' \
      "`id.start_with?('L')` true, `id.size > 1` false"
    ].join("\n")
    assert_output("#{expected}\n") { t.report }
  end

  test '6rTS4j', %w(
  | Example: ns.filter_map do |n| "n#{n}" unless n.nil? end
  | The block's one expression is a modifier unless.
  | The covered file still loads, and filter_map still keeps
  | ["n1", "n2"] of [1, nil, 2].
  ) do |t|
    t.write(<<~'RUBY', 'names.rb')
      module Names
        def self.names(ns)
          ns.filter_map do |n|
            "n#{n}" unless n.nil?
          end
        end
      end
    RUBY
    t.start
    names = t.load('names.rb')::Names
    assert_equal %w(n1 n2), names.names([1, nil, 2])
  end

  test '6rTS4k', %w(
  | Example: report :summary, fee with two ifs called once with
  | true then false
  | At exit it prints a line per total, as SimpleCov prints its
  | line and branch coverage.
  | Within decisions: 2 / 4, one of each if's two paths.
  | Within methods: 2 / 4 too, fee's card having just its two
  | ifs as rows.
  ) do |t|
    t.write(<<~RUBY, 'fee.rb')
      module Fee
        def self.fee(member, big)
          total = 100
          if member
            total -= 5
          end
          if big
            total -= 10
          end
          total
        end
      end
    RUBY
    t.start { report :summary }
    t.load('fee.rb')::Fee.fee(true, false)
    printed = capture_io { t.report }.first
    decisions = "Path coverage within decisions: 2 / 4 (50.00%)\n"
    methods = "Path coverage within methods: 2 / 4 (50.00%)\n"
    assert_equal decisions + methods, printed
  end

  test '6rTS4e', %w(
  | Example: ns.select { |n| n.odd? }
  | odds is called with [], [1], and [1, 2].
  | The covered select still keeps [], [1], and [1].
  | The exit report prints the paths never taken.
  | Eg `ns` 2+ items, `n.odd?` all true.
  ) do |t|
    t.write(<<~RUBY, 'odds.rb')
      module Odds
        def self.odds(ns) = ns.select { |n| n.odd? }
      end
    RUBY
    t.start
    odd = t.load('odds.rb')::Odds
    odds = [[], [1], [1, 2]].map { |ns| odd.odds(ns) }
    assert_equal [[], [1], [1]], odds
    never = 'odds.rb:2:25 path never taken: `ns`'
    expected = [
      "#{never} 1 item, `n.odd?` all false",
      "#{never} 2+ items, `n.odd?` all true",
      "#{never} 2+ items, `n.odd?` all false"
    ].join("\n")
    assert_output("#{expected}\n") { t.report }
  end

  test '6rTS50', %w(
  | starting a second time swaps the configuration silently,
  | with no warning that the load hook was redefined
  ) do
    on_exit = ->(&_report) {}
    assert_silent do
      PathCoverage.start(on_exit:) { root '/app' }
      PathCoverage.start(on_exit:) { root '/app' }
    end
  end

  test '6rTS51', %w(
  | Example: a run with ignore '||=' of @m ||= a && b
  | Its JSON report names ||= as ignored.
  | A render from it, ignoring ||= too, prints the gaps the
  | run printed: those of the && alone.
  ) do |t|
    t.write(<<~RUBY, 'memo.rb')
      module Memo
        def self.m(a, b) = (@m ||= a && b)
      end
    RUBY
    report = nil
    on_exit = ->(&block) { report = block }
    settings = proc do
      root t.dir
      cover '*.rb'
      coverage_dir t.dir
      ignore '||='
    end
    PathCoverage.start(on_exit:, &settings)
    t.load('memo.rb')::Memo.m(true, true)
    live, = capture_io { report.call }
    assert_equal ['||='], t.json['ignored']
    config = PathCoverage::Configuration.new(&settings)
    later, = capture_io { PathCoverage::Render.from_json(config) }
    never = 'memo.rb:2:29 path never taken: `a`'
    expected = "#{never} true, `b` false\n#{never} false\n"
    assert_equal [expected, expected], [live, later]
  end

  test '6rTS52', %w(
  | Example: u.name&.size with treat 'name', as: :present,
  | called with a u whose name is nil
  | The treatment was wrong: name was nil.
  | The exit report says so, naming the path it ruled out,
  | rather than dropping that path unseen.
  ) do |t|
    t.write(<<~RUBY, 'size.rb')
      module Size
        def self.of(u) = u.name&.size
      end
    RUBY
    t.start { treat 'name', as: :present }
    size = t.load('size.rb')::Size
    named = Struct.new(:name)
    sizes = [named.new('kim'), named.new(nil)].map do |u|
      size.of(u)
    end
    assert_equal [3, nil], sizes
    expected = 'size.rb:2:19 path taken that a treatment rules ' \
               "out: `u.name` nil\n"
    assert_output(expected) { t.report }
  end

  test '6rTS53', %w(
  | Example: u.name&.size with treat 'name', as: :present, a
  | name nil in each of two runs
  | Each JSON report holds the path the treatment ruled out.
  | A render from both says so, rather than dropping it.
  ) do |t|
    t.write(<<~RUBY, 'size.rb')
      module Size
        def self.of(u) = u.name&.size
      end
    RUBY
    settings = proc do |out|
      proc do
        root t.dir
        cover '*.rb'
        coverage_dir out
        treat 'name', as: :present
      end
    end
    outs = %w(first second).map { |run| "#{t.dir}/#{run}" }
    reports = outs.map do |out|
      report = nil
      on_exit = ->(&block) { report = block }
      PathCoverage.start(on_exit:, &settings.call(out))
      report
    end
    size = t.load('size.rb')::Size
    nameless = Struct.new(:name).new(nil)
    reports.each do |report|
      size.of(nameless)
      capture_io { report.call }
    end
    jsons = outs.map { |out| "#{out}/path_coverage.json" }
    outside = JSON.parse(File.read(jsons[0]))['outside']
    ruled_out = outside.transform_values do |all|
      all.map { _1['path'] }
    end
    assert_equal({ 'size.rb:2:19' => [['nil']] }, ruled_out)
    config = PathCoverage::Configuration.new(&settings.call(t.dir))
    later, = capture_io { PathCoverage::Render.from_json(config, jsons) }
    line = 'size.rb:2:19 path taken that a treatment rules out: ' \
           "`u.name` nil\n"
    assert_includes later, line
  end

  test '6rTS54', %w(
  | Example: ids.select { |i| i.odd? }.any? && c with treat
  | 'any?', as: :nonempty, called on each of its paths
  | any? true with select keeping nothing can never happen.
  | So no such path is listed as never taken.
  | Every possible path was taken, so nothing is printed.
  ) do |t|
    t.write(<<~RUBY, 'odds.rb')
      module Odds
        def self.k(ids, c) = ids.select { |i| i.odd? }.any? && c
      end
    RUBY
    t.start { treat 'any?', as: :nonempty }
    odds = t.load('odds.rb')::Odds
    calls = [
      [[], true], [[1], true], [[1], false], [[2], true],
      [[1, 3], true], [[1, 3], false], [[2, 4], true],
      [[1, 2], true], [[1, 2], false]
    ]
    calls.each { |ids, c| odds.k(ids, c) }
    assert_output('') { t.report }
  end

  test '6rTS55', %w(
  | Example: user&.account&.owner, called with no user, and
  | with a user whose account has an owner
  | The card shows the chain's rows as user, then account, so
  | they read as the code does.
  | owner has no row: it decides no path, and is called exactly
  | where account is not nil.
  ) do |t|
    t.write(<<~RUBY, 'owner.rb')
      module Owner
        def self.of(user) = user&.account&.owner
      end
    RUBY
    t.start { report }
    owner = t.load('owner.rb')::Owner
    account = Struct.new(:owner).new('kim')
    users = [nil, Struct.new(:account).new(account)]
    assert_equal([nil, 'kim'], users.map { owner.of(_1) })
    t.report

    rows = fold_at(t, 'owner.rb:2')
    texts = of_kind(rows, 'operand').map { shown(_1).first }
    assert_equal %w(user account), texts
  end

  test '6rTS6a', %w(
  | Example: ship, a write then a value, and zero, an endless
  | def of 0, measured within methods, ship called twice and
  | zero once
  | Each def is counted each time it is called, by its own
  | site's name; its write and value, no rows, are not counted.
  | Each method returns what the same code, uninstrumented,
  | returns.
  ) do |t|
    source = lambda do |name|
      <<~RUBY
        module #{name}
          def self.ship(order)
            box = order * 2
            box
          end
          def self.zero = 0
        end
      RUBY
    end
    t.write(source.call('Ship'), 'ship6a.rb')
    t.start
    ship = t.load('ship6a.rb')::Ship
    eval(source.call('Plain6rTS6a')) # rubocop:disable Security/Eval
    calls = ->(mod) { [mod.ship(3), mod.ship(4), mod.zero] }
    plain = calls.call(Plain6rTS6a)
    actual = calls.call(ship)
    assert_equal [[6, 8, 0], plain], [actual, actual]
    expected = { 'ship6a.rb:2:2' => 2, 'ship6a.rb:6:2' => 1 }
    assert_equal expected, PathCoverage.recorder.reached
    assert_output('', '') { t.report }
  end

  test '6rTS6b', %w(
  | Example: ship, a write, a return if empty, then a value,
  | measured within methods, called once with a full order
  | Its card in the HTML report shows each row's taken, and
  | its JSON report holds ship's call-count.
  | The if is its one row, its then never run, so 1 of 2; the
  | write and the value are no rows.
  ) do |t|
    t.write(<<~RUBY, 'ship6b.rb')
      module Ship
        def self.ship(order)
          box = order * 2
          return 0 if box.zero?
          box
        end
      end
    RUBY
    t.start { report }
    t.load('ship6b.rb')::Ship.ship(3)
    t.report
    assert_equal [%w(ship 1), %w(4:13 1)], card_taken(t, 2)
    assert_equal({ 'ship6b.rb:2:2' => 1 }, t.json['reached'])
  end

  test '6rTS6c', %w(
  | Example: label, a ternary whose then arm is an && chain,
  | and mark, an if whose then arm holds only a comment
  | Each arm's row in the ternary's tree is located in the
  | source, its at; the if's tree has no arm rows.
  | The && in label's then arm is located too, its operands
  | with it.
  ) do |t|
    t.write(<<~RUBY, 'label6c.rb')
      module Label
        def self.label(sale, cheap)
          sale ? (cheap && 'bargain') : 'full price'
        end

        def self.mark(ok)
          if ok
            # nothing to mark
          else
            'unmarked'
          end
        end
      end
    RUBY
    t.start { report }
    label = t.load('label6c.rb')::Label
    label.label(true, true)
    label.mark(false)
    t.report
    located = lambda do |line, kind|
      rows = of_kind(fold_at(t, "label6c.rb:#{line}"), kind)
      rows.map { !_1['at'].nil? }
    end
    assert_equal [true, true], located.call(3, 'arm')
    assert_equal [true] * 3, located.call(3, 'operand')
    assert_equal [], located.call(7, 'arm')
  end

  test '6rTS6d', %w(
  | Example: ship, an if then a value, measured within methods,
  | called once with a paid order
  | Its card folds the if's tree under the if's row: its
  | operator, and its operands.
  ) do |t|
    t.write(<<~RUBY, 'ship6d.rb')
      module Ship
        def self.ship(order)
          if order[:paid]
            order[:packed] = true
          end
          order
        end
      end
    RUBY
    t.start { report }
    t.load('ship6d.rb')::Ship.ship({ paid: true })
    t.report
    rows = fold_at(t, 'ship6d.rb:3')
    texts = of_kind(rows, 'operand').map { shown(_1).first }
    assert_equal ['order[:paid]'], texts
  end

  test '6rTS6e', %w(
  | Example: rate.rb, a ?: at its top level, with no RATE set,
  | and fee, a def of a ?:, called once with big true
  | The top level's ?: is on no card, outside every def, so
  | its paths are in the methods total as they are: 1 of 2.
  | So the methods total is fee's card's 1 of 2 and the top
  | level's 1 of 2: [2, 4].
  ) do |t|
    t.write(<<~RUBY, 'rate.rb')
      RATE = ENV.key?('RATE6rTS6e') ? 2 : 1
      module Fee
        def self.fee(big) = big ? 10 : 5
      end
    RUBY
    t.start { report }
    t.load('rate.rb')::Fee.fee(true)
    t.report
    assert_equal [2, 4], t.json['totals']['methods']
  end

  test '6rTS6f', %w(
  | Example: rate.rb, a ?: at its top level, with no RATE set
  | It has a top card for line 1, as a method has a card, with
  | no calls, titled file, its scope: one ?: row, 1 of its 2
  | paths taken.
  ) do |t|
    t.write(<<~RUBY, 'rate.rb')
      RATE = ENV.key?('RATE6rTS6f') ? 2 : 1
    RUBY
    t.start { report }
    t.load('rate.rb')
    t.report
    cards = t.json['cards']
    placed = cards.map { |site, card| [site, card['calls']] }
    assert_equal [['rate.rb:1:0', nil]], placed
    assert_equal [%w(file 1), %w(1:30 1)], card_taken(t, 1)
  end

  test '6rTS6g', %w(
  | Example: rate.rb, module Rate holding a ?: outside any
  | method, with no RATE set
  | Its card is titled Rate, its scope, as a method's card is
  | titled by its method.
  ) do |t|
    t.write(<<~RUBY, 'rate.rb')
      module Rate
        RATE = ENV.key?('RATE6rTS6g') ? 2 : 1
      end
    RUBY
    t.start { report }
    t.load('rate.rb')
    t.report
    assert_equal [%w(Rate 1), %w(2:32 1)], card_taken(t, 2)
  end

  test '6rTS6h', %w(
  | Example: rate.rb, class Rate holding a ?: outside any
  | method, with no RATE set
  | Its card is titled Rate, its scope, as a module's is.
  ) do |t|
    t.write(<<~RUBY, 'rate.rb')
      class Rate
        RATE = ENV.key?('RATE6rTS6h') ? 2 : 1
      end
    RUBY
    t.start { report }
    t.load('rate.rb')
    t.report
    assert_equal [%w(Rate 1), %w(2:32 1)], card_taken(t, 2)
  end

  test '6rTS6j', %w(
  | Example: module Fee holding fee, a def of a ?:, called once
  | with big true
  | The JSON report lists fee's card, under its def's site, as
  | its page draws it: its name, first and last lines, the ways
  | through it, how many times it was called, and a row per
  | statement, with its paths, how many were taken, and its
  | site, so a reader finds a card's gap without the page.
  ) do |t|
    t.write(<<~RUBY)
      module Fee
        def self.fee(big) = big ? 10 : 5
      end
    RUBY
    t.start { report }
    t.load::Fee.fee(true)
    t.report
    expected = {
      "#{t.file}:2:2" => {
        'name' => 'fee', 'first' => 2, 'last' => 2, 'ways' => 2,
        'calls' => 1,
        'rows' => [
          { 'at' => '2:26', 'top' => '?:', 'paths' => 2, 'taken' => 1,
            'site' => "#{t.file}:2:26" }
        ]
      }
    }
    assert_equal expected, t.json['cards']
  end

  test '6rTS6k', %w(
  | Example: module Rate holding a ?: outside any method, with
  | no RATE set
  | The JSON report lists its top card too, under the site of
  | its first line's start, titled Rate, its scope, as its page
  | draws it, so a reader finds a gap outside every def too.
  | It is no method's, so has no calls.
  ) do |t|
    t.write(<<~RUBY, 'rate.rb')
      module Rate
        RATE = ENV.key?('RATE6rTS6k') ? 2 : 1
      end
    RUBY
    t.start { report }
    t.load('rate.rb')
    t.report
    expected = {
      'rate.rb:2:0' => {
        'name' => 'Rate', 'first' => 2, 'last' => 2, 'ways' => 2,
        'calls' => nil,
        'rows' => [
          { 'at' => '2:32', 'top' => '?:', 'paths' => 2, 'taken' => 1,
            'site' => 'rate.rb:2:32' }
        ]
      }
    }
    assert_equal expected, t.json['cards']
  end

  test '6rTS6n', %w(
  | Example: module Fee holding fee, an if of big holding a ?:
  | of vip, called once with big false
  | The JSON report lists how fee's card's rows nest, under its
  | file, then its card, each row by its line:column: the ?:
  | runs in the if's then arm, on its path 0, so a reader can
  | tell which paths reach a row, whatever the run took.
  ) do |t|
    t.write(<<~RUBY)
      module Fee
        def self.fee(big, vip)
          if big
            vip ? 10 : 5
          end
        end
      end
    RUBY
    t.start { report }
    t.load::Fee.fee(false, true)
    t.report
    top = PathCoverage::CardTree::TOP
    inner = { 'parent' => '3:4', 'in' => 'then', 'on' => [0] }
    card = { '3:4' => top, '4:10' => top.merge(inner) }
    assert_equal({ t.file => { '2:2' => card } }, t.json['tree'])
  end

  test '6rTS6p', %w(
  | Example: module Rate holding a ?: outside any method
  | The JSON report lists how its top card's rows nest too,
  | under the card's line:column, as cards names it.
  ) do |t|
    t.write(<<~RUBY, 'rate.rb')
      module Rate
        RATE = ENV.key?('RATE6rTS6p') ? 2 : 1
      end
    RUBY
    t.start { report }
    t.load('rate.rb')
    t.report
    top = PathCoverage::CardTree::TOP
    expected = { 'rate.rb' => { '2:0' => { '2:32' => top } } }
    assert_equal expected, t.json['tree']
  end

  test '6rTS6q', %w(
  | Example: module Pick holding pick, a ?: of a whose then arm
  | is a ?: of b, called with a and b true, then with a false
  | Each ?: is a site, and a row, of its own: the outer took both
  | its paths, the inner, run only in the outer's then arm, its
  | then alone; the tree places the inner in that arm.
  ) do |t|
    t.write(<<~RUBY)
      module Pick
        def self.pick(a, b) = a ? (b ? 1 : 2) : 3
      end
    RUBY
    t.start { report }
    pick = t.load::Pick
    pick.pick(true, true)
    pick.pick(false, true)
    t.report
    rows = t.json['cards']["#{t.file}:2:2"]['rows'].map do |row|
      row.values_at('at', 'top', 'paths', 'taken')
    end
    assert_equal [['2:26', '?:', 2, 2], ['2:31', '?:', 2, 1]], rows
    top = PathCoverage::CardTree::TOP
    inner = { 'parent' => '2:26', 'in' => 'then', 'on' => [0] }
    tree = { '2:26' => top, '2:31' => top.merge(inner) }
    assert_equal tree, t.json['tree'][t.file]['2:2']
  end

  test '6rTS6s', %w(
  | Example: module Pick holding pick, an if of a with an else,
  | and size, an if of a with an elsif, each called once
  | The if's fold is headed if/else, as its card row is, and
  | names where its else keyword is, line 5, columns 4 to 8, so
  | hovering over that else in the code can open the if's fold,
  | as hovering over its if does. An if whose else arm is an
  | elsif is headed if, and has no else keyword, so names none:
  | its elsif is a site, with a fold, of its own.
  ) do |t|
    t.write(<<~RUBY)
      module Pick
        def self.pick(a)
          if a
            1
          else
            2
          end
        end

        def self.size(a)
          if a > 9
            :big
          elsif a > 1
            :some
          end
        end
      end
    RUBY
    t.start { report }
    pick = t.load::Pick
    pick.pick(true)
    pick.size(5)
    t.report
    elses = [3, 11].map do |line|
      first = fold_at(t, "#{t.file}:#{line}").first
      [shown(first).first, first['else']]
    end
    assert_equal [['if/else', [5, 4, 5, 8]], ['if', nil]], elses
  end

  test '6rTS6m', %w(
  | Example: two starts in one process, eg two tests, each over
  | its own rate.rb, a ?: whose site has the same name in both,
  | each evaluated once, with no RATE set
  | Each start records afresh, so the second run's report counts
  | its own one evaluation, not the first run's too.
  ) do |t|
    jsons = %w(first second).map do |run|
      t.write(<<~RUBY, "#{run}/rate.rb")
        RATE = ENV.key?('RATE6rTS6m') ? 2 : 1
      RUBY
      run_dir = "#{t.dir}/#{run}"
      exit_report = nil
      on_exit = ->(&block) { exit_report = block }
      PathCoverage.start(on_exit:) do
        root run_dir
        cover '*.rb'
        coverage_dir run_dir
      end
      t.load("#{run}/rate.rb")
      gap = 'rate.rb:1:30 path never taken: ' \
            "`ENV.key?('RATE6rTS6m')` true\n"
      assert_output(gap) { exit_report.call }
      JSON.parse(File.read("#{run_dir}/path_coverage.json"))
    end
    taken = jsons.last['paths'].values.first['taken']
    assert_equal([0, 1], taken.map { _1['count'] })
  end

  private

  # Example: owner.rb:2 gives the rows of the site on line 2.
  # The rows of the fold of the first site at file:line, as the
  # source report fixture's run wrote has them.
  def fold_at(fixture, line)
    written = File.read("#{fixture.dir}/path_coverage.source.json")
    file = line[/\A(.*):\d+\z/, 1]
    sites = JSON.parse(written)['files'].fetch(file)['sites']
    site = sites.keys.grep(/\A#{Regexp.escape(line)}:/).first
    sites.fetch(site).fetch('fold')
  end

  # Example: ship's card gives [%w(ship 1), %w(4:13 1)].
  # [name, taken] of the card at line first in the JSON report
  # fixture's run wrote, its rows' taken added up, then [at,
  # taken] of each row.
  def card_taken(fixture, first)
    card = card_at(fixture, first)
    rows = card['rows'].map { |row| [row['at'], row['taken']] }
    taken = rows.sum { |_, count| count.to_i }
    [[card['name'], taken], *rows].map { |name, n| [name, n.to_s] }
  end

  # The card at line first in the JSON report fixture's run wrote.
  def card_at(fixture, first)
    cards = fixture.json['cards'].values
    cards.to_h { [_1['first'], _1] }.fetch(first)
  end

  # The rows of rows of kind, eg operand; none when none are.
  def of_kind(rows, kind)
    rows.group_by { _1['kind'] }.fetch(kind, [])
  end

  # Example: a user's row gives ['user', 'present', 'absent'].
  # What a fold row shows: its label's text, then each cell's
  # mark, eg present, or else its text.
  def shown(row)
    cells = row.fetch('cells', []).map do |text, mark|
      [mark, text].compact.first
    end
    [row['label']['text'], *cells]
  end
end
