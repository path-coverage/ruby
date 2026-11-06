require_relative 'test_helper'
require 'path_coverage/source_lines'

class SourceLinesTest < TidTest
  test 'MDBw10', %w(
  | each source line gets its number, its text and a status:
  | nil with no condition, covered when every outcome of its
  | conditions was seen, gaps when any outcome is missing
  ) do
    source = <<~RUBY
      module Kata
        def self.ok?(id) = !id.empty?
        def self.kata?(id) = ok?(id) && id.start_with?('N')
        def self.team?(id) = ok?(id) && id.size == 6
      end
    RUBY
    decisions = {
      'source/kata.rb:3:23' => condition('&&', 67...74, 78...97),
      'source/kata.rb:4:23' => condition('&&', 121...128, 132...144)
    }
    operands = {
      'source/kata.rb:3:23' => [
        { truthy: 1, falsy: 1 },
        { truthy: 1, falsy: 0 }
      ],
      'source/kata.rb:4:23' => [
        { truthy: 2, falsy: 1 },
        { truthy: 1, falsy: 1 }
      ]
    }
    expected = [
      { number: 1, text: 'module Kata', status: nil, span: nil },
      { number: 2, text: '  def self.ok?(id) = !id.empty?',
        status: nil, span: nil },
      { number: 3,
        text: "  def self.kata?(id) = ok?(id) && id.start_with?('N')",
        status: :gaps, span: 3..3 },
      { number: 4,
        text: '  def self.team?(id) = ok?(id) && id.size == 6',
        status: :covered, span: 4..4 },
      { number: 5, text: 'end', status: nil, span: nil }
    ]
    source_lines = PathCoverage::SourceLines
    actual = source_lines.of(source, decisions, operands)
    assert_equal expected, actual
  end

  test 'MDBw15', %w(
  | a line holding a decision with gaps shows gaps,
  | even when another decision on the same line is covered,
  | so a gap is never reported as covered
  ) do
    source = <<~RUBY
      module Kata
        def self.pair?(a, b) = [ok?(a) && new?(a), ok?(b) && new?(b)]
      end
    RUBY
    decisions = {
      'source/kata.rb:2:26' => condition('&&', 38...44, 48...55),
      'source/kata.rb:2:45' => condition('&&', 57...63, 67...74)
    }
    operands = {
      'source/kata.rb:2:26' => [
        { truthy: 1, falsy: 0 },
        { truthy: 1, falsy: 0 }
      ],
      'source/kata.rb:2:45' => [
        { truthy: 2, falsy: 1 },
        { truthy: 1, falsy: 1 }
      ]
    }
    source_lines = PathCoverage::SourceLines
    line = source_lines.of(source, decisions, operands)[1]
    assert_equal :gaps, line[:status]
  end

  test 'MDBw16', %w(
  | a line whose only unseen outcome is the impossible one
  | of a leaf that can have one outcome only is covered
  ) do
    source = <<~RUBY
      def initialize(options)
        @clock = options[:clock] || MonotonicClock.new
      end
    RUBY
    fixed = { 54...72 => :truthy }
    decisions = {
      'source/clock.rb:2:11' =>
        condition('||', 35...50, 54...72, fixed:)
    }
    operands = {
      'source/clock.rb:2:11' => [
        { truthy: 1, falsy: 1 },
        { truthy: 1, falsy: 0, only: :truthy }
      ]
    }
    source_lines = PathCoverage::SourceLines
    line = source_lines.of(source, decisions, operands)[1]
    assert_equal :covered, line[:status]
  end

  test 'MDBw17', %w(
  | decisions whose lines overlap merge into one span,
  | so all the lines they cover form a single button
  ) do
    source = <<~RUBY
      module Kata
        def self.pair?(a, b) = [ok?(a) &&
          new?(a), ok?(b) && new?(b)]
      end
    RUBY
    decisions = {
      'source/kata.rb:2:26' => condition('&&', 38...44, 52...59),
      'source/kata.rb:3:13' => condition('&&', 61...67, 71...78)
    }
    operands = {
      'source/kata.rb:2:26' => [
        { truthy: 1, falsy: 1 },
        { truthy: 1, falsy: 1 }
      ],
      'source/kata.rb:3:13' => [
        { truthy: 1, falsy: 1 },
        { truthy: 1, falsy: 1 }
      ]
    }
    source_lines = PathCoverage::SourceLines
    lines = source_lines.of(source, decisions, operands)
    expected = [nil, 2..3, 2..3, nil]
    actual = lines.map { |line| line[:span] }
    assert_equal expected, actual
  end

  test 'MDBw20', %w(
  | a condition written over several lines puts all of them
  | in one span, so their line numbers form a single button
  | and its tree can open below the last of them
  ) do
    source = <<~RUBY
      module Kata
        def self.kata?(id)
          ok?(id) &&
            id.start_with?('N')
        end
      end
    RUBY
    decisions = {
      'source/kata.rb:3:4' => condition('&&', 37...44, 54...73)
    }
    operands = {
      'source/kata.rb:3:4' => [
        { truthy: 1, falsy: 1 },
        { truthy: 1, falsy: 0 }
      ]
    }
    expected = [
      { number: 1, text: 'module Kata', status: nil, span: nil },
      { number: 2, text: '  def self.kata?(id)', status: nil,
        span: nil },
      { number: 3, text: '    ok?(id) &&', status: :gaps,
        span: 3..4 },
      { number: 4, text: "      id.start_with?('N')", status: :gaps,
        span: 3..4 },
      { number: 5, text: '  end', status: nil, span: nil },
      { number: 6, text: 'end', status: nil, span: nil }
    ]
    source_lines = PathCoverage::SourceLines
    actual = source_lines.of(source, decisions, operands)
    assert_equal expected, actual
  end
end
