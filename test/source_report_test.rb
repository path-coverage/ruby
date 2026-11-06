require_relative 'test_helper'
require 'path_coverage/configuration'
require 'path_coverage/manifest'
require 'path_coverage/source_report'

class SourceReportTest < TidTest
  test 'Sj3r10', %w(
  | Example: def ok?(id) = id.size == 6 # six
  | each line of a file's source, as the source report has it:
  | its text and its coloured tokens, so a renderer can draw
  | the code without parsing it
  ) do
    source = "def ok?(id) = id.size == 6 # six\nok?(1)\n"
    expected = [
      {
        text: 'def ok?(id) = id.size == 6 # six',
        tokens: [[0, 3, 'k'], [25, 26, 'n'], [27, 32, 'c']]
      },
      { text: 'ok?(1)', tokens: [[4, 5, 'n']] }
    ]
    assert_equal expected, PathCoverage::SourceReport.lines(source)
  end

  test 'Sj3r20', %w(
  | Example: ok?(id) && new?(id)
  | a decision, as the source report has it: the lines it spans
  | and its fold's rows, headed by its row's top, with a column
  | per path in the order the JSON report lists them, and no
  | counts, which the JSON report has
  ) do
    source = "def kata?(id)\n  ok?(id) && new?(id)\nend\n"
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    paths = [
      { path: [true, true], count: 1 },
      { path: [true, false], count: 0 },
      { path: [false, nil], count: 2 }
    ]
    expected = {
      span: [2, 2],
      fold: [
        { kind: 'decision', branch: '',
          label: { text: '&&', tokens: [[0, 2, 'o']] },
          at: [2, 2, 2, 21], else: nil },
        { kind: 'operand', branch: 'ths',
          label: { text: 'ok?(id)', tokens: [] }, at: [2, 2, 2, 9],
          cells: [['T', nil, nil], ['T', nil, nil],
                  ['F', nil, nil]] },
        { kind: 'operand', branch: 'lhs',
          label: { text: 'new?(id)', tokens: [] }, at: [2, 13, 2, 21],
          cells: [['T', nil, nil], ['F', nil, nil], ['', nil, nil]] }
      ]
    }
    report = PathCoverage::SourceReport
    decision = report.decision(source, decisions, 'k.rb:2:2', paths,
                               '&&')
    assert_equal expected, decision
  end

  test 'Sj3r30', %w(
  | the source report of a run: the operators ignored, the
  | covered files of each group, each card row's top coloured,
  | and each covered file's lines and decisions, each
  | decision's fold headed by its card row's top
  ) do
    source = "def kata?(id)\n  ok?(id) && new?(id)\nend\n"
    decisions = PathCoverage::Manifest.decisions(source, 'k.rb')
    files = { '/app/k.rb' => { source:, decisions: } }
    config = PathCoverage::Configuration.new do
      root '/app'
      cover 'k.rb'
      group 'Katas', 'k*.rb'
      group 'Other', 'x.rb'
    end
    paths = [
      { path: [true, true], count: 1 },
      { path: [true, false], count: 0 },
      { path: [false, nil], count: 2 }
    ]
    decision_paths = { 'k.rb:2:2' => paths }
    row = { 'decision' => 'k.rb:2:2', 'top' => '&&' }
    leave = { 'decision' => nil, 'top' => 'return' }
    cards = { 'k.rb:1:0' => { 'rows' => [row, leave] } }
    report = PathCoverage::SourceReport
    decision = report.decision(source, decisions, 'k.rb:2:2', paths,
                               '&&')
    expected = {
      '$schema': 'https://path-coverage.github.io/schemas/v1/' \
                 'path_coverage.source.schema.json',
      schema: 1, ignored: [],
      groups: { 'Katas' => ['k.rb'], 'Other' => [] },
      labels: {
        '&&' => { text: '&&', tokens: [[0, 2, 'o']] },
        'return' => { text: 'return', tokens: [[0, 6, 'k']] }
      },
      files: {
        'k.rb' => {
          lines: report.lines(source),
          decisions: { 'k.rb:2:2' => decision }
        }
      }
    }
    assert_equal expected,
                 report.of(files, config, decision_paths, cards)
  end

  test 'Sj3r40', %w(
  | a group holds every covered file its globs match, all of
  | them or none
  ) do
    kata = "def kata?(id) = id.size == 6\n"
    kits = "def kits = 3\n"
    files = {
      '/app/kata.rb' => { source: kata, decisions: {} },
      '/app/kits.rb' => { source: kits, decisions: {} }
    }
    config = PathCoverage::Configuration.new do
      root '/app'
      cover 'k*.rb'
      group 'Katas', 'k*.rb'
      group 'Other', 'x.rb'
    end
    report = PathCoverage::SourceReport.of(files, config, {}, {})
    expected = { 'Katas' => %w(kata.rb kits.rb), 'Other' => [] }
    assert_equal expected, report[:groups]
  end

  test 'Sj3r50', %w(
  | a run that loaded no covered file has no files, and each
  | group none of them
  ) do
    config = PathCoverage::Configuration.new do
      root '/app'
      cover 'k*.rb'
      group 'Katas', 'k*.rb'
    end
    report = PathCoverage::SourceReport.of({}, config, {}, {})
    assert_equal({ 'Katas' => [] }, report[:groups])
    assert_equal({}, report[:files])
  end

  test 'Sj3r60', %w(
  | a group of several globs holds a file any of them matches;
  | a group of no globs holds none
  ) do
    kata = "def kata = 6\n"
    files = {
      '/app/models/kata.rb' => { source: kata, decisions: {} },
      '/app/lib/zip.rb' => { source: "def zip = 5\n", decisions: {} }
    }
    config = PathCoverage::Configuration.new do
      root '/app'
      cover '**/*.rb'
      group 'Models', 'app/models/*.rb', 'models/*.rb'
      group 'Empty'
    end
    report = PathCoverage::SourceReport.of(files, config, {}, {})
    expected = { 'Models' => ['models/kata.rb'], 'Empty' => [] }
    assert_equal expected, report[:groups]
  end
end
