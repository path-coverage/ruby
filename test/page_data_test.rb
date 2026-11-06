require_relative 'test_helper'
require 'path_coverage/page_data'

class PageDataTest < TidTest
  test 'Hd7a10', %w(
  | Example: shop.rb, 1 of its 3 method paths taken, and a group
  | holding no file
  | The index's data has a table per tab, each row's percent
  | rounded, and none, nil, when no path is possible, so the
  | page shows - rather than dividing by zero.
  ) do
    row = { path: 'source/shop.rb', sites: 2, decisions: [2, 4],
            methods: [1, 3] }
    none = { sites: 0, decisions: [0, 0], methods: [0, 0] }
    tables = [['All files', [row], row], ['Admin', [], none]]

    data = PathCoverage::PageData.index(tables, ['&&='])

    expected = {
      schema: 1, page: 'index',
      tables: [
        { name: 'All files',
          rows: [{ path: 'source/shop.rb', sites: 2,
                   methods: [1, 3], percent: 33 }],
          total: { sites: 2, methods: [1, 3], percent: 33 } },
        { name: 'Admin', rows: [],
          total: { sites: 0, methods: [0, 0], percent: nil } }
      ],
      ignored: ['&&=']
    }
    assert_equal expected, data
  end

  test 'Hd7a20', %w(
  | Example: def ship(order) with an if at 43:4 and
  | return total if order[:pickup] dropped to its return row at
  | 50:4
  | A card's data has its title's numbers worked out: the paths
  | not taken, and taken, over its rows. A site's row has its
  | fold; a return row, no site, has none, and its fold is
  | never asked for.
  ) do
    card = {
      'name' => 'ship', 'first' => 42, 'last' => 53, 'ways' => 4,
      'calls' => 2,
      'rows' => [
        { 'at' => '43:04', 'site' => 'source/shop.rb:43:4',
          'top' => 'if/else', 'paths' => 2, 'taken' => 1 },
        { 'at' => '50:04', 'site' => nil, 'top' => 'return',
          'paths' => 1, 'taken' => 1 }
      ]
    }
    place = { first: 42, last: 53, column: 2, status: 'gaps',
              top: false, sites: nil }
    asked = []
    data = PathCoverage::PageData.card(card, place) do |site, top|
      asked << [site, top]
      [{ kind: 'site' }]
    end

    assert_equal [['source/shop.rb:43:4', 'if/else']], asked
    title = { name: 'ship', calls: 2, ways: 4, notTaken: 1, taken: 2 }
    assert_equal place.merge(title:), data.except(:rows)
    rows = data[:rows]
    folds = rows.map { _1[:fold] }
    assert_equal [[{ kind: 'site' }], nil], folds
    tops = rows.map { _1[:top] }
    if_else = { text: 'if/else', tokens: [[0, 2, 'k'], [3, 7, 'k']] }
    assert_equal [if_else, { text: 'return', tokens: [[0, 6, 'k']] }],
                 tops
  end

  test 'Hd7a30', %w(
  | Example: line 43 of shop.rb, if order[:gift] &&, in a span of
  | sites over lines 43 to 44, and line 49, blank
  | A file page's data has each line's text and tokens, and the
  | status and span of the sites it is in, nil for a line in
  | none.
  ) do
    lines = [
      { number: 43, text: '    if order[:gift] &&', status: :gaps,
        span: 43..44, tokens: [[4, 6, 'k'], [20, 22, 'o']] },
      { number: 49, text: '', status: nil, span: nil, tokens: [] }
    ]

    data = PathCoverage::PageData.file('source/shop.rb', lines, [])

    expected = {
      schema: 1, page: 'file', path: 'source/shop.rb',
      lines: [
        { text: '    if order[:gift] &&', status: 'gaps',
          span: [43, 44], tokens: [[4, 6, 'k'], [20, 22, 'o']] },
        { text: '', status: nil, span: nil, tokens: [] }
      ],
      cards: []
    }
    assert_equal expected, data
  end

  test 'Hd7a40', %w(
  | Example: initialize, a def with no statements, called once,
  | then never called; ship, its if taken one way of two; and
  | pick, its if/else taken both ways and its return taken
  | A card is covered only when every row took all its paths and
  | its method was called: initialize called once has no path it
  | could leave untaken; never called, it ran none of its code,
  | so it has a gap; ship's untaken path is a gap; pick took
  | every path of both its rows.
  ) do
    initialize = ->(calls) { { 'calls' => calls, 'rows' => [] } }
    ship = {
      'calls' => 3,
      'rows' => [{ 'paths' => 2, 'taken' => 1 }]
    }
    pick = {
      'calls' => 2,
      'rows' => [{ 'paths' => 2, 'taken' => 2 },
                 { 'paths' => 1, 'taken' => 1 }]
    }
    cards = [initialize.call(1), initialize.call(0), ship, pick]
    statuses = cards.map { PathCoverage::PageData.status(_1) }
    assert_equal %w(covered gaps gaps covered), statuses
  end
end
