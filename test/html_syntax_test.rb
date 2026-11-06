require_relative 'test_helper'
require 'path_coverage/html_syntax'

class HtmlSyntaxTest < TidTest
  test 'Sx7h10', %w(
  | Example: def ok?(id) = id.size == 6 # six
  | def is a keyword, 6 a number and # six a comment.
  | Each is a [from, to, class] range of the line's columns.
  | The other tokens are not coloured, so have no range.
  ) do
    source = "def ok?(id) = id.size == 6 # six\n"
    expected = { 1 => [[0, 3, 'k'], [25, 26, 'n'], [27, 32, 'c']] }
    assert_equal expected, PathCoverage::HtmlSyntax.of(source)
  end

  test 'Sx7h11', %w(
  | Example: x = "hi" if :a
  | A string's quotes and content are one string range.
  | A symbol's colon and name are one string range too.
  ) do
    source = "x = \"hi\" if :a\n"
    expected = { 1 => [[4, 8, 's'], [9, 11, 'k'], [12, 14, 's']] }
    assert_equal expected, PathCoverage::HtmlSyntax.of(source)
  end

  test 'Sx7h12', %w(
  | Example: a string over two lines, then "é" # x on a third
  | A token over two lines has a range on each.
  | Columns count characters, not bytes, so é is one column.
  ) do
    source = "x = \"a\nb\"\n\"é\" # x\n"
    expected = {
      1 => [[4, 6, 's']],
      2 => [[0, 2, 's']],
      3 => [[0, 3, 's'], [4, 7, 'c']]
    }
    assert_equal expected, PathCoverage::HtmlSyntax.of(source)
  end

  test 'Sx7h14', %w(
  | Example: a constant, a label and an instance variable, then
  | a %w array and a regexp, then a heredoc
  | A constant is t and an instance variable v.
  | A label, a %w array, a regexp and a heredoc are each a string.
  | The heredoc's body and its end each have their own range.
  ) do
    source = "X = { kind: @k }\n%w[a b] =~ /x/\ny = <<~E\n  hi\nE\n"
    expected = {
      1 => [[0, 1, 't'], [6, 11, 's'], [12, 14, 'v']],
      2 => [[0, 7, 's'], [11, 14, 's']],
      3 => [[4, 8, 's']],
      4 => [[0, 4, 's']],
      5 => [[0, 1, 's']]
    }
    assert_equal expected, PathCoverage::HtmlSyntax.of(source)
  end

  test 'Sx7h15', %w(
  | Example: x = " then a line break, then b"
  | The string's content starts with the line break.
  | So on line 1 it has no characters, and no range there.
  | Line 1's range is the opening quote alone.
  ) do
    source = "x = \"\nb\"\n"
    expected = { 1 => [[4, 5, 's']], 2 => [[0, 2, 's']] }
    assert_equal expected, PathCoverage::HtmlSyntax.of(source)
  end

  test 'Sx7h16', %w(
  | Example: x = a && b || c&.d ? 1 : 2, then @m ||= 1
  | &&, ||, &., a ternary's ? and :, and ||= each decide a path.
  | So each is o, coloured as an operator that decides.
  ) do
    source = "x = a && b || c&.d ? 1 : 2\n@m ||= 1\n"
    expected = {
      1 => [[6, 8, 'o'], [11, 13, 'o'], [15, 17, 'o'], [19, 20, 'o'],
            [21, 22, 'n'], [23, 24, 'o'], [25, 26, 'n']],
      2 => [[0, 2, 'v'], [3, 6, 'o'], [7, 8, 'n']]
    }
    assert_equal expected, PathCoverage::HtmlSyntax.of(source)
  end

  test 'Sx7h17', %w(
  | Example: the fragments &&, ||, &., ?:, if and id.size == 6,
  | as a site's tree shows them
  | Each is coloured as the code it is part of.
  | &&, ||, &. and ?: name the operators that decide a path, so
  | each is coloured as one, though alone ?: lexes as a character
  | and || as two pipes.
  ) do
    texts = ['&&', '||', '&.', '?:', 'if', 'id.size == 6']
    tokens = texts.map do |text|
      PathCoverage::HtmlSyntax.code(text)[:tokens]
    end
    expected = [
      [[0, 2, 'o']], [[0, 2, 'o']], [[0, 2, 'o']], [[0, 2, 'o']],
      [[0, 2, 'k']], [[11, 12, 'n']]
    ]
    assert_equal expected, tokens
  end

  test 'Sx7h18', %w(
  | Example: name = @user&.name
  | @user and &. touch, but are of different classes.
  | So each keeps a range of its own, not joined.
  ) do
    ranges = PathCoverage::HtmlSyntax.of("name = @user&.name\n")
    assert_equal({ 1 => [[7, 12, 'v'], [12, 14, 'o']] }, ranges)
  end
end
