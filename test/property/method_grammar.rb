# Generates small Ruby methods from a grammar of the statements
# that decide a method's paths or leave it. Each leaf is a
# boolean parameter, so calling a method on every combination of
# its parameters takes every path it can. Seeded, so a seed always
# gives the same method.
# Each leaf is a fresh parameter by default, so every path is
# taken. With reuse, a leaf is as often one already drawn, so
# leaves correlate, eg return t if p0 then t += p0 ? 1 : 2, whose
# true path no call can take, and the method has three top-level
# statements, so a guard can come before two that read its leaf.
class MethodGrammar
  # The statements that leave the method.
  LEAVES = ['return t', 'raise Stop'].freeze

  # The predicates of an if or unless, a and b fresh leaves.
  CONDITIONS = [
    '%<a>s', '(%<a>s && %<b>s)', '%<a>s || %<b>s',
    '(%<a>s and %<b>s)', '(%<a>s or %<b>s)'
  ].freeze

  # The statements that hold no body, for any level.
  FLAT = {
    plain: 't += 1',
    modifier: '%<leave>s if %<leaf>s',
    either: '%<leaf>s or return t',
    both: '%<leaf>s and return t',
    ternary: 't += %<leaf>s ? 1 : 2'
  }.freeze

  # The statements that hold bodies of their own, for the top
  # level only, so a method nests at most one deep.
  NESTING = {
    if: "if %<cond>s\n%<body>s\nelse\n%<other>s\nend",
    unless: "unless %<cond>s\n%<body>s\nend"
  }.freeze

  # A body's one statement: flat, or one that leaves, which ends
  # the body, so no code follows it.
  BODY = FLAT.merge(leave: '%<leave>s').freeze

  # How many top-level statements a method has, by whether its
  # leaves can repeat.
  TOPS = { false => 2, true => 3 }.freeze

  # The rescue a rescued method ends with, catching its raises.
  RESCUE = "rescue Stop\n-1".freeze

  # The loop a looped method starts with. Its body is a statement
  # that can end its pass, then a flat one.
  LOOPS = { loop: "[0, 1].each do\n%<pass>s\n%<then>s\nend" }.freeze

  # The first statement of a loop's body. It ends the pass with
  # next, the loop with break, or the method with a leave, each
  # only on a leaf, so the statement after it can run.
  PASS = { skip: 'next if %<leaf>s', stop: 'break if %<leaf>s',
           modifier: FLAT.fetch(:modifier) }.freeze

  # The rescues a nested method starts with. A begin with a rescue
  # of its own, a rescue modifier, or a begin whose rescue retries
  # once. Each body can raise Stop, which its rescue catches.
  NESTED = {
    begun: "begin\n%<body>s\nrescue Stop\nt -= 1\nend",
    modified: '(%<leave>s if %<leaf>s) rescue t -= 1',
    retried: "tries = 0\nbegin\n%<body>s\nrescue Stop\ntries += 1\n" \
             "retry if tries < 2\nend"
  }.freeze

  # Example: MethodGrammar.new(7).source is a method of seed 7.
  # With reuse: true its leaves can repeat. With rescued: true its
  # own rescue catches its raises. With looped: true its first
  # statement is a loop. With nested: true its first statement is
  # one of NESTED.
  def initialize(seed, reuse: false, rescued: false, looped: false,
                 nested: false)
    @random = Random.new(seed)
    @leaves = 0
    @reuse = reuse
    @rescued = rescued
    @looped = looped
    @nested = nested
  end

  # The source of a module Snippet holding Stop, the error its
  # raises raise, and run. run's parameters are its leaves. It has
  # two top-level statements, three with reuse, after t = 0, and
  # a loop first when looped, or one of NESTED first when nested.
  # Its value is t. Rescued, half the
  # time its value is its last statement's instead, which can
  # leave, and a rescue of Stop gives -1.
  def source
    top = FLAT.merge(NESTING)
    statements = Array.new(TOPS.fetch(@reuse)) { statement(top) }
    statements.unshift(statement(LOOPS)) if @looped
    statements.unshift(statement(NESTED)) if @nested
    statements << 't' unless @rescued && @random.rand(2).zero?
    statements << RESCUE if @rescued
    snippet(statements.join("\n"))
  end

  private

  # The module Snippet whose run's parameters are the leaves so
  # far, its body after t = 0.
  def snippet(body)
    params = Array.new(@leaves) { "p#{_1}" }.join(', ')
    <<~RUBY
      module Snippet
        class Stop < StandardError; end

        def self.run(#{params})
          t = 0
      #{body}
        end
      end
    RUBY
  end

  # One statement, its kind drawn from kinds, its pieces filled.
  def statement(kinds)
    template = kinds.values.sample(random: @random)
    names = template.scan(/%<(\w+)>s/).flatten.uniq
    format(template, names.to_h { [_1.to_sym, send(:"#{_1}_piece")] })
  end

  # A leaf: with reuse, once there is one, half the time a
  # parameter already drawn; else the next parameter.
  def leaf_piece
    return reused_piece if @reuse && @leaves.positive? &&
                           @random.rand(2).zero?

    @leaves += 1
    "p#{@leaves - 1}"
  end

  # A parameter already drawn, any of them.
  def reused_piece
    "p#{@random.rand(@leaves)}"
  end

  # The first leaf of a predicate.
  def a_piece = leaf_piece

  # The second leaf of a predicate.
  def b_piece = leaf_piece

  # A predicate of an if or unless.
  def cond_piece
    statement(CONDITIONS.to_h { [_1, _1] })
  end

  # A statement that leaves the method.
  def leave_piece
    LEAVES.sample(random: @random)
  end

  # The body of an if's then arm, or an unless's.
  def body_piece
    statement(BODY)
  end

  # The body of an if's else arm.
  def other_piece = body_piece

  # The first statement of a loop's body.
  def pass_piece
    statement(PASS)
  end

  # The second statement of a loop's body.
  def then_piece
    statement(FLAT)
  end
end
