require_relative 'manifest'
require_relative 'method_statements'
require_relative 'decision_paths'
require_relative 'decision_tree'

module PathCoverage
  # How the rows of each card nest: for each row, the decision it
  # runs inside, the arm of that decision it is in, and the paths of
  # that decision on which it runs, so a reader can tell which paths
  # reach a row, and count the paths through a card as a whole.
  module CardTree
    # Part of a decision's code that a row can be inside: an arm of
    # statements, or a leaf; owner the key of the decision's row,
    # range its bytes, arm its arm's name, nil for a leaf, on
    # the indices of the decision's possible paths that run it, and
    # leaf a leaf's index among the decision's leaves, nil for an arm.
    Region = Data.define(:owner, :range, :arm, :on, :leaf)

    # The place of a row inside no other row's decision.
    TOP = {
      'parent' => nil, 'in' => nil, 'on' => nil,
      'leaf' => nil, 'gives' => nil
    }.freeze

    # Example: def f(a); if a then 1 end; end gives the value
    # row 1 its parent, the if, in its then arm, on its path 0.
    # { def decision => { "line:column" => { 'parent' =>, 'in' =>,
    # 'on' =>, 'leaf' =>, 'gives' => } } } for each def in
    # source, a row keyed by where it is named. parent is the
    # "line:column" of the decision the row runs inside, in the name
    # of its arm, on the indices of that decision's possible paths,
    # as DecisionPaths.possible orders them, that run the row, leaf
    # the index of that decision's leaf holding it, and gives, for a
    # row whose decision is the whole of that leaf, the leaf's
    # outcome on each of the row's own possible paths, nil where
    # not known; each nil where it does not apply.
    def self.of(source, path, decisions = nil)
      decisions = Manifest.decisions(source, path) if decisions.nil?
      cards = MethodStatements.of(source, path, decisions)
      cards.transform_values { nested(source, decisions, _1) }
    end

    # { "line:column" => its place } for each of rows, a card's,
    # each placed in the innermost region of another row's
    # decision holding all of its own decision's code, or, for a
    # row that is no decision, where it starts: a decision
    # starting where its child does, eg an || whose first operand
    # is an any?, holds that child, and is not held by it.
    def self.nested(source, decisions, rows)
      starts = line_starts(source)
      regions = card_regions(source, decisions, rows)
      rows.to_h do |row|
        at = starts[row.line - 1] + row.column
        decision = row.decision ? decisions.fetch(row.decision) : nil
        span = decision ? decision.extent : at...(at + 1)
        key = key_of(row)
        [key, placed(key, span, regions, decision)]
      end
    end

    # The regions of the decisions of rows, a card's, decisions being
    # { decision => Condition }.
    def self.card_regions(source, decisions, rows)
      rows.select(&:decision).flat_map do |row|
        regions_of(source, key_of(row), decisions.fetch(row.decision))
      end
    end

    # The place of the row keyed key, its code the bytes span,
    # decision its Condition, nil for a row that is no decision:
    # in the decision owning the smallest region of another row
    # holding span, as place gives it; TOP for a row in no such
    # region.
    def self.placed(key, span, regions, decision)
      holding = holding(key, span, regions)
      inner = smallest(holding)
      return TOP if inner.nil?

      owner = inner.owner
      own = holding.group_by(&:owner).fetch(owner)
      place(owner, own).merge(leaf_place(own, decision))
    end

    # The leaf and gives of a row's place, own being the regions
    # of its parent holding it, decision its Condition: the index of
    # the innermost leaf holding it; and, when decision is the whole
    # of that leaf, decision's value on each of its possible paths,
    # as its kind gives them, the leaf's outcome there. Neither
    # for a row that is no decision, a return or a raise, which gives
    # its parent nothing.
    def self.leaf_place(own, decision)
      return { 'leaf' => nil, 'gives' => nil } if decision.nil?

      leaf = smallest(own.reject(&:arm))
      whole = leaf && decision.extent == leaf.range
      gives = whole ? DecisionPaths.values(decision) : nil
      { 'leaf' => leaf&.leaf, 'gives' => gives }
    end

    # The regions of regions holding all of the bytes span, but
    # for those of the row keyed key itself.
    def self.holding(key, span, regions)
      held = regions.group_by do |region|
        region.owner != key && region.range.cover?(span)
      end
      held.fetch(true, [])
    end

    # A row's place in the decision of the row keyed owner, own being
    # the regions of that decision holding the row: the innermost arm
    # of them, nil for none, and the paths on which every one of
    # them runs, as the row runs only where all of them do.
    def self.place(owner, own)
      arm = smallest(own.select(&:arm))
      on = own.map(&:on).reduce(:&)
      { 'parent' => owner, 'in' => arm&.arm, 'on' => on }
    end

    # The region of regions with the fewest bytes; nil for none.
    def self.smallest(regions)
      regions.min_by { |region| region.range.size }
    end

    # The regions of condition, the decision of the row keyed owner:
    # its arms', and its leaves'.
    def self.regions_of(source, owner, condition)
      possible = DecisionPaths.possible(condition)
      node = DecisionTree.node(source, condition, possible,
                               (0..).each)
      arm_regions(owner, condition, node) +
        leaf_regions(owner, condition, possible)
    end

    # The regions of condition's leaves, in no arm, each run on
    # the paths of possible with an outcome at its index.
    def self.leaf_regions(owner, condition, possible)
      condition.leaves.each_with_index.map do |range, index|
        skipped = possible.each_index.group_by do |i|
          possible[i][index].nil?
        end
        on = skipped.fetch(false)
        Region.new(owner:, range:, arm: nil, on:, leaf: index)
      end
    end

    # The regions of the arms in condition, node its tree, each
    # operand's node at its own index: of its own arms, and of
    # those of each condition nested in it, in an operand or in
    # an arm's body.
    def self.arm_regions(owner, condition, node)
      built = condition.operands.zip(node[:operands])
      built.flat_map do |operand, operand_node|
        case operand
        when Condition then arm_regions(owner, operand, operand_node)
        when Arm then arm_region(owner, operand, operand_node)
        else []
        end
      end
    end

    # The regions of arm, node its node: its own, named by its
    # kind and run on the paths that take it, none for an arm
    # with no statements, which holds no row; then its body's.
    def self.arm_region(owner, arm, node)
      body = arm.body ? arm_regions(owner, arm.body, node[:body]) : []
      return body if arm.extent.nil?

      cells = node[:cells]
      on = cells.each_index.group_by { cells[_1] }.fetch(true, [])
      own = Region.new(owner:, range: arm.extent, arm: arm.kind.to_s,
                       on:, leaf: nil)
      [own, *body]
    end

    # The "line:column" key of row, from its name.
    def self.key_of(row)
      row.name.split(':').last(2).join(':')
    end

    # The byte offset where each line of source starts, first
    # line first.
    def self.line_starts(source)
      source.each_line.reduce([0]) do |starts, line|
        starts << (starts.last + line.bytesize)
      end
    end
  end
end
