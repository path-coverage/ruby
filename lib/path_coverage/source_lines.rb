require_relative 'gaps'

module PathCoverage
  # The lines of one file's page, each with the status of the
  # conditions on it.
  module SourceLines
    # [{number:, text:, status:, span:}] for each line of
    # source. A line in a decision's span shares one button with
    # the span's other lines; status and span are nil on a line
    # with no condition.
    def self.of(source, decisions, operands)
      marks = marks(source, decisions, operands)
      source.lines.each_with_index.map do |text, index|
        number = index + 1
        mark = marks.fetch(number, {})
        {
          number:, text: text.chomp,
          status: mark[:status], span: mark[:span]
        }
      end
    end

    # { line number => {status:, span:} } for each line a decision
    # covers, every line of a merged span sharing that span.
    def self.marks(source, decisions, operands)
      blocks = merged(spans_of(source, decisions, operands))
      blocks.each_with_object({}) do |(span, status), marks|
        span.each { |number| marks[number] = { status:, span: } }
      end
    end

    # [span, status] for each decision: from the line it starts on
    # to the line its last operand ends on.
    def self.spans_of(source, decisions, operands)
      decisions.map do |decision, condition|
        last = condition.leaves.last
        span = line_of(decision)..end_line(source, last)
        [span, status_of(operands.fetch(decision))]
      end
    end

    # The spans merged wherever they overlap, in line order. A
    # merged span has :gaps if any of its decisions has, so a
    # covered decision never hides another's gaps.
    def self.merged(spans)
      sorted = spans.sort_by { |span, _| span.begin }
      sorted.each_with_object([]) do |(span, status), blocks|
        last_span, last_status = blocks.last
        if last_span && last_span.end >= span.begin
          joined = last_span.begin..[last_span.end, span.end].max
          blocks[-1] = [joined, worse(last_status, status)]
        else
          blocks << [span, status]
        end
      end
    end

    # :gaps if either status is :gaps, else :covered.
    def self.worse(one, other)
      [one, other].include?(:gaps) ? :gaps : :covered
    end

    # :covered when no operand has a gap, else :gaps.
    def self.status_of(counts)
      gaps = counts.flat_map { |operand| Gaps.operand_gap(operand) }
      gaps.empty? ? :covered : :gaps
    end

    # The line a decision starts on, from its path:line:column name.
    def self.line_of(decision)
      decision[/:(\d+):\d+\z/, 1].to_i
    end

    # The line of source on which byte range ends.
    def self.end_line(source, range)
      source.byteslice(0, range.end).count("\n") + 1
    end
  end
end
