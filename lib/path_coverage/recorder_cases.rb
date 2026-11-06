module PathCoverage
  # The part of the recorder that notes a case nested in another
  # decision, eg (case a when 1 then b end) && c: the decision
  # around it enters and leaves, so its patterns only note
  # whether they matched. It relies on its includer's record.
  module RecorderCases
    # A stand-in for the pattern of a case nested in decision, its
    # match noted as the decision's index-th leaf.
    NestedMatch = Struct.new(:recorder, :decision, :index,
                             :pattern) do
      # Whether pattern matches subject, exactly as pattern says,
      # noted on the decision's path.
      def ===(subject)
        recorder.record(decision, index, pattern === subject)
      end
    end

    # The stand-in for pattern, the index-th leaf of decision, in a
    # case nested in it.
    def pattern(decision, index, pattern)
      NestedMatch.new(self, decision, index, pattern)
    end
  end
end
