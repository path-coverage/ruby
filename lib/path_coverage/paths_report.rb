module PathCoverage
  # What the reports say about each decision's paths beyond their
  # counts, worked out from each covered file's source: where
  # each leaf is, and what it says.
  module PathsReport
    # { decision => { leaves:, taken: } }: taken is each path and
    # its count, as Result#paths gives them, and leaves each
    # leaf's ["line:column", "line:column"] span, so a tool can
    # recover each leaf exactly. files is { full path =>
    # {source:, decisions:} }.
    def self.of(decision_paths, files)
      spans = leaf_spans(files)
      decision_paths.to_h do |decision, taken|
        [decision, { leaves: spans.fetch(decision), taken: }]
      end
    end

    # { decision => [each leaf's source text] } for every decision in
    # files.
    def self.texts(files)
      each_decision(files) do |source, condition|
        condition.leaves.map { |range| source.byteslice(range) }
      end
    end

    # { decision => [each leaf's span] } for every decision in files.
    def self.leaf_spans(files)
      each_decision(files) do |source, condition|
        condition.leaves.map do |range|
          [at(source, range.begin), at(source, range.end)]
        end
      end
    end

    # { decision => what the block makes of its file's source and
    # its condition } for every decision in files.
    def self.each_decision(files)
      files.values.each_with_object({}) do |parsed, all|
        parsed[:decisions].each do |decision, condition|
          all[decision] = yield(parsed[:source], condition)
        end
      end
    end

    # "line:column" of a byte offset in source, the line from
    # 1 and the column, in characters, from 0, as decision names
    # count them.
    def self.at(source, offset)
      before = source.byteslice(0, offset)
      line = before.count("\n") + 1
      start = before.rindex("\n")
      "#{line}:#{before.length - (start ? start + 1 : 0)}"
    end
  end
end
