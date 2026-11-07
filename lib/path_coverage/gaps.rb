module PathCoverage
  # The terminal worklist: one line per path a decision never
  # took, and nothing for a decision that took them all. Every
  # count stays in the operands and paths for reporters that
  # show them all.
  module Gaps
    # The gap lines of operands, paths and outside, as Result
    # gives them, in manifest order; texts is { decision => each
    # leaf's source text }. A decision's first leaf runs before any
    # other, so a decision whose first never ran was never reached.
    def self.lines(operands, paths: {}, texts: {}, outside: {})
      operands.flat_map do |decision, counts|
        next ["#{decision} never reached"] if never_ran?(counts.first)

        path_gaps(decision, paths.fetch(decision, []),
                  texts[decision]) +
          ruled_out(decision, outside.fetch(decision, {}),
                    texts[decision])
      end
    end

    # One line per path decision took that a treatment rules out,
    # as Result#outside gives them, texts being each leaf's
    # source text.
    def self.ruled_out(decision, taken, texts)
      taken.keys.map do |path|
        "#{decision} path taken that a treatment rules out: " \
          "#{steps(path, texts)}"
      end
    end

    # Example: ["k.rb:5:11 path taken that its method rules out:
    # `a` true"].
    # One line per path taken, or return or raise reached, that
    # its method rules out, ruled as CardContext.ruled_out gives
    # them, texts being { decision => each leaf's source text }.
    # Such a line shows a fact derived from the code to be wrong.
    def self.ruled_by_method(ruled, texts)
      ruled.map do |name, path|
        reached = "#{name} reached, though its method rules it out"
        next reached if path.nil?

        "#{name} path taken that its method rules out: " \
          "#{steps(path, texts[name])}"
      end
    end

    # The outcome of each leaf path reaches, each named by its
    # text, eg "`u.name` nil". A path's first leaf always has an
    # outcome, so it always has a step.
    def self.steps(path, texts)
      path.zip(texts).each_with_object([]) do |(outcome, text), all|
        all << "#{code(text)} #{outcome}" unless outcome.nil?
      end.join(', ')
    end

    # One line per path decision never took, as Result#paths gives
    # them, naming the outcome of each leaf the path reaches,
    # texts being each leaf's source text.
    def self.path_gaps(decision, paths, texts)
      paths.each_with_object([]) do |each, lines|
        next unless each[:count].zero?

        named = steps(each[:path], texts)
        lines << "#{decision} path never taken: #{named}"
      end
    end

    # text as a markdown code span on one line: each run of
    # whitespace one space, fenced by a run of backticks one
    # longer than any inside it, with a space inside the fence
    # when text starts or ends with one.
    def self.code(text)
      text = text.gsub(/\s+/, ' ')
      longest = text.scan(/`+/).map(&:size).max || 0
      fence = '`' * (longest + 1)
      pad = text.start_with?('`') || text.end_with?('`') ? ' ' : ''
      "#{fence}#{pad}#{text}#{pad}#{fence}"
    end

    # The one outcome this operand is missing, if any; a fixed
    # leaf, which can have one outcome only, needs only to run.
    def self.operand_gap(counts)
      return ['never evaluated'] if never_ran?(counts)
      return [] if counts[:only]
      return ['never true'] if counts[:truthy].zero?
      return ['never false'] if counts[:falsy].zero?

      []
    end

    # True when the operand was never recorded either way.
    def self.never_ran?(counts)
      counts[:truthy].zero? && counts[:falsy].zero?
    end
  end
end
