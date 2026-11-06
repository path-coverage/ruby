require 'fileutils'
require_relative 'html_cards'
require_relative 'html_data'
require_relative 'html_syntax'
require_relative 'html_template'
require_relative 'site_tree'
require_relative 'source_lines'
require_relative 'summary'
require_relative 'within_methods'

module PathCoverage
  # The :html reporter: index.html, and files/<path>.html for
  # each covered file, written to the configuration's
  # output_dir. Each page is its data, as HtmlData gives it, in
  # the shared renderer's page, as HtmlTemplate writes it.
  module HtmlReport
    # Writes every page. recorded is [site_paths, reached]:
    # site_paths, like operands, as Result gives them, holding
    # every site in files; reached as Recorder#reached gives it,
    # nil when not known. files is { full path => {source:,
    # sites:} } for each covered file, as the kernel parsed it.
    # The files dir is emptied first, so it holds no page for a
    # file no longer covered.
    def self.write(operands, files, config, recorded)
      site_paths, reached = recorded
      dir = config.output_dir
      FileUtils.rm_rf("#{dir}/files")
      cards = WithinMethods.cards(files, config, site_paths, reached)
      index = index(config, site_paths, cards)
      File.write("#{dir}/index.html", index)
      write_pages(operands, files, config, recorded)
    end

    # Writes each covered file's page, recorded as write has it,
    # with its methods' cards.
    def self.write_pages(operands, files, config, recorded)
      files.each do |full_path, parsed|
        path = config.relative(full_path)
        cards = HtmlCards.methods(path, parsed, recorded)
        out = "#{config.output_dir}/files/#{path}.html"
        write_page(out, path, parsed, [operands, recorded[0]], cards)
      end
    end

    # The index page: a row per file of its totals within each
    # decision, and, when cards are given, as they are when
    # methods are measured, within each method too, its defs'
    # cards added up; then their Total row. With groups
    # configured, each group, and the files in none, get a tab
    # of their own too. Any operators config ignored are named
    # after them.
    def self.index(config, site_paths, cards)
      rows = Summary.files(site_paths, cards)
      groups = config.groups
      tabs = groups.empty? ? [] : Summary.groups(rows, groups)
      ignored = config.ignored
      tables = [['All files', rows, Summary.total(rows)], *tabs]
      HtmlTemplate.page(HtmlData.index(tables, ignored))
    end

    # Writes one file's page to out, from its sites' operand
    # counts and paths, with cards, its methods', then a card for
    # each span of its sites at the top level.
    def self.write_page(out, path, parsed,
                        (operands, site_paths), cards)
      source, sites = parsed.values_at(:source, :sites)
      plain = SourceLines.of(source, sites, operands)
      lines = coloured(source, plain)
      tops = HtmlCards.tops(path, parsed, [operands, site_paths])
      data = HtmlData.file(path, lines, cards + tops)
      page = HtmlTemplate.page(data)
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, page)
    end

    # lines, as SourceLines.of gives them for source, each with
    # its coloured tokens, as HtmlSyntax.of gives them.
    def self.coloured(source, lines)
      tokens = HtmlSyntax.of(source)
      lines.map do |line|
        line.merge(tokens: tokens.fetch(line[:number], []))
      end
    end

    # simplecov:disable
    # SPIKE: tree with an at: of [line, column, line, column]
    # on it and on each of its operands: a leaf's from its byte
    # range, a condition's and an arm's from its extent, the
    # whole of it as written. Columns count characters, not
    # bytes. A node past the condition's operands, eg owner at
    # the end of user&.account&.owner, is kept as it is.
    def self.located(source, condition, tree)
      pairs = condition.operands.zip(tree[:operands])
      operands = pairs.map do |operand, node|
        located_operand(source, operand, node)
      end
      rest = tree[:operands].drop(pairs.size)
      tree.merge(at: at(source, condition.extent),
                 operands: operands + rest)
    end

    # SPIKE: the node of operand with its at:, as located gives
    # a condition's, an arm's or a leaf's.
    def self.located_operand(source, operand, node)
      case operand
      when Condition then located(source, operand, node)
      when Arm then located_arm(source, operand, node)
      else node.merge(at: at(source, operand))
      end
    end

    # An arm's node with its at:, nil for an arm with no
    # statements, and its body's tree located.
    def self.located_arm(source, arm, node)
      body = arm.body ? located(source, arm.body, node[:body]) : nil
      at = arm.extent ? at(source, arm.extent) : nil
      node.merge(at:, body:)
    end

    # [line, column, line, column] of the byte range in source.
    def self.at(source, range)
      [*position(source, range.begin), *position(source, range.end)]
    end

    # [line, column] of a byte offset in source.
    def self.position(source, offset)
      before = source.byteslice(0, offset)
      newline = before.rindex("\n")
      column = before.length - (newline ? newline + 1 : 0)
      [before.count("\n") + 1, column]
    end
    # simplecov:enable
  end
end
