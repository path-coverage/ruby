require 'prism'

module PathCoverage
  # The colours of a file's code on its page: each token Prism
  # lexes, as Ruby itself does, gets the class of its kind, eg k
  # for a keyword, so the page's CSS colours it.
  module CodeTokens
    # The class of each coloured token type that is not a keyword
    # or a number: c comment, s string, t constant, v instance
    # variable, o an operator that decides a path.
    CLASSES = {
      COMMENT: 'c', CONSTANT: 't', INSTANCE_VARIABLE: 'v',
      **%i[
        AMPERSAND_AMPERSAND PIPE_PIPE AMPERSAND_DOT QUESTION_MARK
        COLON AMPERSAND_AMPERSAND_EQUAL PIPE_PIPE_EQUAL
      ].to_h { |type| [type, 'o'] },
      **%i[
        STRING_BEGIN STRING_CONTENT STRING_END SYMBOL_BEGIN LABEL
        PERCENT_LOWER_W WORDS_SEP REGEXP_BEGIN REGEXP_END
        HEREDOC_START HEREDOC_END
      ].to_h { |type| [type, 's'] }
    }.freeze

    # { line number => [[from, to, class], ...] } for the lines of
    # source that have coloured tokens, columns counting
    # characters, a token over many lines having a range on each,
    # touching ranges of one class joined.
    def self.of(source)
      layout = Layout.new(source)
      pairs = classed(source).flat_map do |from, to, css|
        layout.ranges(from, to).map do |number, first, last|
          [number, [first, last, css]]
        end
      end
      pairs.group_by(&:first).transform_values do |line|
        joined(line.map(&:last).sort)
      end
    end

    # A source's lines, by the byte offset each starts at.
    class Layout
      # The lines of source, line 1 starting at byte 0.
      def initialize(source)
        @source = source
        @starts = [0]
        source.each_line do |line|
          @starts << (@starts.last + line.bytesize)
        end
      end

      # [[line number, first column, last column], ...] for each
      # line the bytes from...to reach, columns counting characters
      # and kept within the line: from the line holding from to the
      # last starting before to. The last start is the source's
      # size, so both searches always find a line.
      def ranges(from, to)
        first = @starts.bsearch_index { |start| start > from } - 1
        last = @starts.bsearch_index { |start| start >= to }
        reached = (first...last).map { |n| columns(n, from, to) }
        reached.compact
      end

      # [line number, first column, last column] of the bytes
      # from...to on the index-th line; nil when none are on it.
      def columns(index, from, to)
        start = @starts[index]
        size = @starts[index + 1] - start
        text = @source.byteslice(start, size).chomp
        first = chars(text, from - start)
        last = chars(text, to - start)
        first < last ? [index + 1, first, last] : nil
      end

      # How many characters of text its first bytes bytes hold.
      def chars(text, bytes)
        text.byteslice(0, bytes.clamp(0, text.bytesize)).length
      end
    end

    # [[from, to, class], ...], the byte range and class of each
    # coloured token of source; a symbol's name is coloured as
    # its colon is.
    def self.classed(source)
      previous = nil
      Prism.lex(source).value.filter_map do |token, _|
        css = class_of(token.type, previous)
        previous = token.type
        location = token.location
        css && [location.start_offset, location.end_offset, css]
      end
    end

    # The class of a token of type, after one of type previous;
    # nil for a token left uncoloured.
    def self.class_of(type, previous)
      return 's' if previous == :SYMBOL_BEGIN

      name = type.to_s
      return 'k' if name.start_with?('KEYWORD_')
      return 'n' if name.start_with?('INTEGER', 'FLOAT')

      CLASSES[type]
    end

    # ranges, in order, each touching one of the same class joined
    # to it.
    def self.joined(ranges)
      ranges.each_with_object([]) do |(from, to, css), out|
        last = out.last
        if last && last[1] == from && last[2] == css
          last[1] = to
        else
          out << [from, to, css]
        end
      end
    end

    # The names of the operators that decide a path, as a decision
    # tree's labels write them. Alone, some lex as other tokens,
    # eg ?: as a character and || as two pipes, so each is
    # coloured as an operator by name.
    DECIDING = %w[&& || &. ?: &&= ||=].freeze

    # Example: x && y as { text: 'x && y', tokens: [[2, 4, 'o']] }.
    # text, a fragment of code on one line, eg a decision tree's
    # operator or operand, as page data holds it: its text and the
    # [from, to, class] of each range coloured as the code it is
    # part of; one of DECIDING wholly the operator it names.
    def self.code(text)
      return { text:, tokens: [[0, text.length, 'o']] } if
        DECIDING.include?(text)

      { text:, tokens: of(text).fetch(1, []) }
    end

    # Example: if/else, each of if and else a keyword.
    # The code of a row's or a fold's label, coloured as code
    # colours it; but a label naming a choice and its else, eg
    # if/else, each of its words, as code would read /else as a
    # regexp's start.
    def self.label_code(text)
      return code(text) unless text.match?(%r{\A\w+/else\z})

      words = text.split('/').map { code(_1) }
      words.reduce { |one, other| joined_code(one, '/', other) }
    end

    # Example: ? total > 100, its ? coloured as an operator.
    # The code of a ternary's arm's label: its ? or : coloured as
    # an operator, the code after it as code.
    def self.ternary_arm_code(label)
      mark, code = label.split(' ', 2)
      marked = { text: mark, tokens: [[0, mark.length, 'o']] }
      joined_code(marked, ' ', code(code.to_s))
    end

    # Example: if, / and else give if/else, its else's ranges moved
    # on by 3.
    # The code of one, then between, uncoloured, then other.
    def self.joined_code(one, between, other)
      shift = one[:text].length + between.length
      moved = other[:tokens].map do |from, to, css|
        [from + shift, to + shift, css]
      end
      { text: one[:text] + between + other[:text],
        tokens: one[:tokens] + moved }
    end
  end
end
