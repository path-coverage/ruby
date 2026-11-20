require_relative 'gaps'
require_relative 'method_ways'

module PathCoverage
  # The terminal worklist of the untested paths through each
  # method: for each method, a heading, then each path no run
  # took, as the choices a test must make to take it.
  module CardGaps
    # The instruction under a method's untested paths.
    UNTESTED = 'Add tests that take each of these paths:'.freeze
    # The instruction under a method with more paths than
    # --max-paths allows.
    TOO_MANY = 'Split it into smaller functions.'.freeze
    # The instruction under the impossible paths a method's calls
    # took.
    DECLARED = 'Remove the # path: impossible comment that ' \
               'declares it:'.freeze

    # The lines of cards, { method's key => card }, as a JSON
    # report has them, each choice's leaves named by their text in
    # texts, { decision => [text, ...] }; a decision whose parent,
    # in parents, { decision => its parent decision }, is stepped
    # on the same path is named there, and the parent left out. A
    # method's card listing no gaps, its ways more than max paths
    # allows, is named with what to do, so it fails and never
    # reads as tested; a top card, run by no call, has no lines.
    def self.lines(cards, texts, parents)
      cards.flat_map do |key, card|
        next [] unless card.key?('taken')

        card_lines(key, card, texts, parents)
      end
    end

    # The lines of card, the method's at key, as lines gives them.
    def self.card_lines(key, card, texts, parents)
      where = "#{key.split(':')[..-2].join(':')} #{card['name']}()"
      return too_many(where, card) unless card.key?('gaps')

      named = Choices.new(card, texts, parents)
      gaps = card['gaps']
      taken = card['impossible_taken']
      section("#{where} has #{paths(gaps.size, 'untested ')}.",
              UNTESTED, gaps, named) +
        section("#{where} took #{paths(taken.size, '')} declared " \
                'impossible.', DECLARED, taken, named)
    end

    # The lines of card, the method's at where, with more paths
    # than --max-paths allows: how many, and what to do.
    def self.too_many(where, card)
      ["#{where} has #{card['ways']} paths, more than " \
       '--max-paths allows.', TOO_MANY]
    end

    # heading and instruction, then each of ways numbered, its
    # choices as named gives them; no lines at all when ways is
    # empty.
    def self.section(heading, instruction, ways, named)
      return [] if ways.empty?

      numbered = ways.each_with_index.map do |way, index|
        "  #{index + 1}. #{named.of(way)}"
      end
      [heading, instruction, *numbered]
    end

    # count paths, of kind, eg "untested ", singular for one.
    def self.paths(count, kind)
      "#{count} #{kind}#{count == 1 ? 'path' : 'paths'}"
    end

    # The choices of a card's ways, as a test must make them.
    class Choices
      # The choices of card's ways, its rows naming each step's
      # decision, texts and parents as CardGaps.lines has them.
      def initialize(card, texts, parents)
        @decisions = card['rows'].to_h { [_1['at'], _1['decision']] }
        @texts = texts
        @parents = parents
      end

      # The choices of way, a path's steps, in order: each stepped
      # decision by its line and its leaves' outcomes, but for a
      # parent of another of them; each loop, a step at no row, by
      # its line and how many items it ran; a step with no choice
      # is left out.
      def of(way)
        stepped = []
        way.each { |step| stepped << step if step.key?('path') }
        implied = implied_by(stepped)
        kept = []
        stepped.each do |step|
          decision = @decisions[step['at']]
          kept << choice(step) unless implied.include?(decision)
        end
        kept.join(', then ')
      end

      # The parent decisions of the decisions stepped steps, each
      # named on its child's step instead; none of a loop's step,
      # which has no decision.
      def implied_by(stepped)
        implied = Set.new
        stepped.each do |step|
          parent = @parents[@decisions[step['at']]]
          implied << parent if parent
        end
        implied
      end

      private

      # One step's choice, after its line: a decision's leaves'
      # outcomes, or a fork's path, a loop's or a rescue's.
      def choice(step)
        line = step['at'].split(':').first
        decision = @decisions[step['at']]
        path = step['path']
        return "line #{line} #{forked(path.first)}" if decision.nil?

        "line #{line} #{Gaps.steps(path, @texts[decision])}"
      end

      # A fork's path, labelled as MethodWays labels it: a loop's
      # items, as FORKS has them; else a rescue's, its body
      # completing or which of its rescues runs.
      def forked(label)
        return "loop: #{label}" if MethodWays::FORKS.include?(label)
        return 'rescue: body completes' if label == 'completed'

        "rescue: #{label} runs"
      end
    end
  end
end
