require_relative 'code_tokens'
require_relative 'method_statements'

module PathCoverage
  # The data of each page of the HTML report, as the shared
  # renderer's schema.json has it: what the page draws, every
  # number it shows that is not a plain count worked out here, so
  # the page and the console never disagree.
  module PageData
    # The version of schema.json the data follows.
    SCHEMA = 1

    # Example: an index of one file, ship.rb, no groups.
    # The index page's data: tables, [name, rows, total] for All
    # files then each group, rows and total as Summary gives them,
    # and the operators ignored.
    def self.index(tables, ignored)
      shown = tables.map do |name, rows, total|
        rows = rows.map { |row| { path: row[:path], **totals(row) } }
        { name:, rows:, total: totals(total) }
      end
      { schema: SCHEMA, page: 'index', tables: shown, ignored: }
    end

    # A row's sites, its [taken, possible] paths within each
    # method, and their percent, rounded; nil with none possible.
    def self.totals(row)
      methods = row[:methods]
      { sites: row[:sites], methods:, percent: percent(methods) }
    end

    # Example: [1, 3] gives 33, [0, 0] nil.
    # The percent of possible paths taken, rounded; nil when none
    # is possible.
    def self.percent((taken, possible))
      possible.zero? ? nil : (100.0 * taken / possible).round
    end

    # A file page's data: the file at path, its lines, as
    # HtmlReport.coloured gives them, and its cards, as card gives
    # each.
    def self.file(path, lines, cards)
      {
        schema: SCHEMA, page: 'file', path:,
        lines: lines.map { |line| line_of(line) }, cards:
      }
    end

    # Example: a card whose rows took all their paths, its method
    # called, gives covered.
    # card's status, as WithinMethods.card gives it: covered when
    # every row's taken is known and is all of its paths, and its
    # method was called, if it is a method's; gaps otherwise, as a
    # row not known may have one, and a method never called, even
    # of no rows, ran none of its code.
    def self.status(card)
      rows = card['rows']
      done = rows.all? { |row| row['taken'] == row['paths'] } &&
             card['calls'] != 0
      done ? 'covered' : 'gaps'
    end

    # One line's data: its text and tokens, and the status and
    # [first, last] span of the sites it is in, nil for none.
    def self.line_of(line)
      span = line[:span]
      {
        text: line[:text], tokens: line[:tokens],
        status: line[:status]&.to_s,
        span: span && [span.begin, span.end]
      }
    end

    # The data of a card, as WithinMethods.card gives it, placed
    # as place has it: its first and last lines, its column, its
    # status, whether it is a top card, and a top card's count of
    # sites. fold gives the rows of a site's fold, from the site
    # and its row's top.
    def self.card(card, place, &fold)
      rows = card['rows']
      rows = rows.map { |row| row_of(row, &fold) }
      place.merge(title: title(card, card['rows']), rows:)
    end

    # The title of card: its name, how many times its method was
    # called, its ways, and how many of its rows' paths were not
    # taken, and how many were.
    def self.title(card, rows)
      taken = rows.map { _1['taken'] }.compact.sum
      size = MethodStatements.size(rows.map { _1['paths'] })
      {
        name: card['name'].to_s, calls: card['calls'],
        ways: card['ways'], notTaken: size - taken, taken:
      }
    end

    # One card row's data, as the JSON report lists it, its top
    # coloured, and a site's row its fold.
    def self.row_of(row, &fold)
      site = row['site']
      {
        at: row['at'], site:, top: CodeTokens.label_code(row['top']),
        paths: row['paths'], taken: row['taken'],
        fold: (fold.call(site, row['top']) if site)
      }
    end
  end
end
