module PathCoverage
  # The algebras CardWays can fold a card's ways in, each giving
  # no ways, the one way through no rows, the one way taking a
  # labelled path, and ways added and joined one after another.
  # A way's label at a row is [row key, path index].
  module WayAlgebras
    # Ways as how many there are.
    module Counted
      # No ways.
      def self.zero = 0

      # The one way through no rows.
      def self.one = 1

      # The one way that takes the path label names.
      def self.unit(_label) = 1

      # The ways of ways, then those of more.
      def self.plus(ways, more) = ways + more

      # Each way of ways going on to each way of more.
      def self.times(ways, more) = ways * more
    end

    # Ways as the labels taken on any of them, so a row's paths
    # that no way takes are those whose labels are missing.
    module Labelled
      # No labels.
      def self.zero = []

      # The one way through no rows, taking no label.
      def self.one = []

      # The one way that takes the path label names.
      def self.unit(label) = [label]

      # The labels of ways or of more.
      def self.plus(ways, more) = ways | more

      # The labels of each way of ways going on to each of more:
      # every one of either, as CardWays never joins no ways.
      def self.times(ways, more) = ways | more
    end

    # Ways as a list of them, each the labels it takes.
    module Listed
      # No ways.
      def self.zero = []

      # The one way through no rows, taking no label.
      def self.one = [[]]

      # The one way that takes the path label names.
      def self.unit(label) = [[label]]

      # The ways of ways, then those of more.
      def self.plus(ways, more) = ways + more

      # Each way of ways going on to each way of more, its labels
      # then theirs.
      def self.times(ways, more)
        ways.product(more).map { |before, after| before + after }
      end
    end

    # Ways in an algebra, each noting an assignment, { local name =>
    # outcome }, as a tally, { assignment => ways in the algebra }.
    # Ways whose assignments disagree, giving a name both outcomes,
    # join into no way, as no call can take them.
    class Tallied
      # Ways in algebra, one of the modules above.
      def initialize(algebra)
        @algebra = algebra
      end

      # No ways.
      def zero = {}

      # The one way through no rows, assigning nothing.
      def one = { {} => @algebra.one }

      # The one way that takes the path label names, with
      # assignment.
      def unit(label, assignment = {})
        { assignment => @algebra.unit(label) }
      end

      # The ways of tally, then those of more, those of one
      # assignment added up.
      def plus(tally, more)
        tally.merge(more) { |_, ways, others| add(ways, others) }
      end

      # Each way of tally going on to each way of more, but for
      # those whose assignments disagree.
      def times(tally, more)
        pairs = tally.to_a.product(more.to_a)
        pairs.reduce(zero) do |all, ((was, ways), (now, others))|
          next all unless agree?(was, now)

          joint = @algebra.times(ways, others)
          plus(all, { was.merge(now) => joint })
        end
      end

      # The ways of tally, whatever their assignments, in the
      # algebra.
      def total(tally)
        each = tally.values
        each.reduce(@algebra.zero) { |all, ways| add(all, ways) }
      end

      private

      # The ways of ways, then those of others, in the algebra.
      def add(ways, others)
        @algebra.plus(ways, others)
      end

      # True when the assignments was and now give no name both
      # outcomes.
      def agree?(was, now)
        was.all? { |name, value| now.fetch(name, value) == value }
      end
    end
  end
end
