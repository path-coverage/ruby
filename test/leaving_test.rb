require_relative 'test_helper'
require 'prism'
require 'path_coverage/leaving'

class LeavingTest < TidTest
  test 'Lv7W10', %w(
  | Example: return :waiting
  | A return leaves the method, so its word is return.
  ) do
    assert_equal 'return', word_of('return :waiting')
  end

  test 'Lv7W11', %w(
  | Example: raise ArgumentError, 'no id'
  | A call of raise with no receiver leaves the method, so its
  | word is raise.
  ) do
    assert_equal 'raise', word_of("raise ArgumentError, 'no id'")
  end

  test 'Lv7W12', %w(
  | Example: kata.raise(:alarm)
  | A call of a method named raise on a receiver is a plain
  | call, so it has no word.
  ) do
    assert_nil word_of('kata.raise(:alarm)')
  end

  test 'Lv7W13', %w(
  | Example: return :done if kata[:finished]
  | A modifier return leaves only when its predicate holds, so
  | the statement, an if, has no word.
  ) do
    assert_nil word_of('return :done if kata[:finished]')
  end

  test 'Lv7W14', %w(
  | Example: total -= 2
  | A write does not leave the method, so it has no word.
  ) do
    assert_nil word_of('total -= 2')
  end

  test 'Lv7W15', %w(
  | Example: if kata[:started] then return :ready end
  | An arm's word is its first statement's, here return.
  ) do
    statements = arm_statements(<<~RUBY)
      if kata[:started]
        return :ready
      end
    RUBY
    assert_equal 'return', PathCoverage::Leaving.of(statements)
  end

  test 'Lv7W16', %w(
  | Example: if kata[:started] end
  | An arm with no statements has no word.
  ) do
    statements = arm_statements(<<~RUBY)
      if kata[:started]
      end
    RUBY
    assert_nil PathCoverage::Leaving.of(statements)
  end

  test 'Lv7W17', %w(
  | Example: fail ArgumentError, 'no id'
  | fail is raise by another name, so it leaves the method and
  | its word is fail.
  ) do
    assert_equal 'fail', word_of("fail ArgumentError, 'no id'")
  end

  test 'Lv7W18', %w(
  | Example: throw :found, kata
  | throw leaves the method for its catch, so its word is
  | throw.
  ) do
    assert_equal 'throw', word_of('throw :found, kata')
  end

  test 'Lv7W19', %w(
  | Example: if order[:pickup] then total -= 2; return total end
  | An arm that returns after a first statement still leaves the
  | method, so its word is return.
  ) do
    statements = arm_statements(<<~RUBY)
      if order[:pickup]
        total -= 2
        return total
      end
    RUBY
    assert_equal 'return', PathCoverage::Leaving.of(statements)
  end

  private

  # Leaving's word for the one statement of code.
  def word_of(code)
    statement = Prism.parse(code).value.statements.body.first
    PathCoverage::Leaving.word(statement)
  end

  # The then arm's statements of the if that is code, nil for an
  # arm with none.
  def arm_statements(code)
    Prism.parse(code).value.statements.body.first.statements
  end
end
