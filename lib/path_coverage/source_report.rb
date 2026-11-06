require_relative 'code_tokens'
require_relative 'fold_rows'
require_relative 'site_locations'
require_relative 'site_tree'
require_relative 'source_lines'
require_relative 'summary'

module PathCoverage
  # What a renderer needs of each covered file beyond the JSON
  # report's counts, worked out from its source, so it can draw
  # the file's page without parsing the source itself.
  module SourceReport
    # The version of the source report's shape.
    SCHEMA = 1

    # The source report of a run: config's ignored operators, the
    # covered files of each of config's groups, each top of the
    # rows of cards, { def site => card }, coloured, and each of
    # files', { full path => {source:, sites:} }, lines and
    # sites, each site's paths as site_paths has them, its fold
    # headed by its row's top.
    def self.of(files, config, site_paths, cards)
      rows = cards.values.flat_map { _1['rows'] }
      tops = rows.to_h { [_1['site'], _1['top']] }
      shown = files.to_h do |full_path, parsed|
        [config.relative(full_path), file(parsed, site_paths, tops)]
      end
      { schema: SCHEMA, ignored: config.ignored,
        groups: groups(config, shown.keys), labels: labels(rows),
        files: shown }
    end

    # { top => it coloured } of each distinct top of rows, a
    # site's or a statement's, eg return.
    def self.labels(rows)
      rows.map { _1['top'] }.uniq.to_h do |top|
        [top, CodeTokens.label_code(top)]
      end
    end

    # { name => the paths its globs match } of each of config's
    # groups.
    def self.groups(config, paths)
      config.groups.transform_values do |globs|
        paths.select { Summary.matches?(_1, globs) }
      end
    end

    # One file's lines and sites, parsed being its {source:,
    # sites:}.
    def self.file(parsed, site_paths, tops)
      source, sites = parsed.values_at(:source, :sites)
      shown = sites.keys.to_h do |name|
        paths = site_paths.fetch(name)
        [name, site(source, sites, name, paths, tops.fetch(name))]
      end
      { lines: lines(source), sites: shown }
    end

    # Example: "ok?(1)\n" gives [{ text: 'ok?(1)', tokens:
    # [[4, 5, 'n']] }].
    # Each line of source: its text and its coloured tokens.
    def self.lines(source)
      tokens = CodeTokens.of(source)
      source.lines.each_with_index.map do |text, index|
        { text: text.chomp, tokens: tokens.fetch(index + 1, []) }
      end
    end

    # Example: ok?(id) && new?(id) on line 2 gives span [2, 2].
    # The site named name, of sites, { name => Condition }, in
    # source: the [first, last] lines it spans, and its fold's
    # rows, headed by top, its row's top, a column for each of
    # paths, [{path:, count:}], in their order, with no counts.
    def self.site(source, sites, name, paths, top)
      condition = sites.fetch(name)
      last = SourceLines.end_line(source, condition.leaves.last)
      span = [SourceLines.line_of(name), last]
      { span:, fold: fold(source, condition, paths, top) }
    end

    # The rows of condition's fold, headed by top, its site row
    # with no counts.
    def self.fold(source, condition, paths, top)
      outcomes = paths.map { _1[:path] }
      tree = SiteTree.built(source, condition, outcomes)
      located = SiteLocations.located(source, condition, tree)
      else_at = SiteLocations.else_at(source, condition)
      own, *rest = FoldRows.rows(located.merge(else_at:, label: top))
      [own.except(:counts), *rest]
    end
  end
end
