require_relative 'condition'
require_relative 'code_tokens'
require_relative 'fold_branches'
require_relative 'fold_cells'
require_relative 'kinds'

module PathCoverage
  # The tree of a site, from SiteTree.of, as its row's fold in a
  # card shows it: a grid whose columns are the site's paths, as
  # page data holds its rows, each a kind, a branch, a label,
  # where its code is and a cell per path.
  module FoldRows
    # The rows of site's fold, as page data holds them: site's own
    # row, naming its operator and each path's count, and where its
    # else keyword is, if it has one; then the rows of its
    # operands.
    def self.rows(site)
      text = site.fetch(:label) { site[:operator] }
      label = CodeTokens.label_code(text)
      own = { kind: 'site', branch: '', label:, at: site[:at],
              else: site[:else_at], counts: site[:counts] }
      [own, *operand_rows(site, '')]
    end

    # The rows of a condition's operands, each branching from
    # its operator after indent; a nested condition's operands,
    # and those of an arm's condition, follow its own row,
    # indented under its branch. A leaf with sites inside it
    # branches as those sites, then the leaf, in the order they
    # run.
    def self.operand_rows(condition, indent)
      own = Kinds.of(condition[:operator]).rows(condition, indent)
      return own if own

      operands = unfolded(shown(condition))
      last = operands.size - 1
      operands.each_with_index.flat_map do |operand, i|
        tip = i == last
        branch = indent + (tip ? FoldBranches::ELL : FoldBranches::TEE)
        under = indent + (tip ? FoldBranches::GAP : FoldBranches::BAR)
        node_rows(operand, branch, under)
      end
    end

    # The rows of one operand of a condition, branching after
    # branch, any operands of its own indented to under.
    def self.node_rows(operand, branch, under)
      return arm_rows(operand, branch, under) if operand.key?(:arm)
      return [leaves_row(operand, branch)] if operand.key?(:leaves)
      return [operand_row(operand, branch)] unless operand[:operator]

      [subtree_row(operand, branch), *operand_rows(operand, under)]
    end

    # The row of an arm that leaves the method, as leaving gives
    # it: return or raise, coloured as code, marking each path
    # that leaves there, placed at its code.
    def self.leaves_row(node, branch)
      cells = FoldCells.values(node[:cells], FoldCells::LEAVES)
      label = CodeTokens.code(node[:leaves])
      { kind: 'leaves', branch:, label:, at: node[:at], cells: }
    end

    # A ternary's arm's row, ? for then and : for else: an arm
    # holding a condition showing the condition's operator and
    # value, its operands below; a plain arm its text, marking
    # the paths taking it.
    def self.arm_rows(arm, branch, under)
      body = arm[:body]
      label = CodeTokens.ternary_arm_code(Kinds::Choice.arm_label(arm))
      row = { kind: 'arm', branch:, label:, at: arm[:at],
              cells: arm_cells(arm, body) }
      body ? [row, *operand_rows(body, under)] : [row]
    end

    # The cells of arm's row: its body's values, when its body is
    # a condition; else a tick on each path that took it.
    def self.arm_cells(arm, body)
      return FoldCells.values(body[:cells]) if body

      FoldCells.values(arm[:cells], FoldCells::TAKEN)
    end

    # The operands of condition a card's fold shows: a ?:'s arms,
    # as its arms are part of its one expression; for any other,
    # eg an if, a ||= or a case, no arm, as which arm a path takes
    # follows from its leaves, but each arm's body, eg a when's
    # patterns, which are leaves of its own, and, for an arm that
    # returns or raises, where paths leave the method.
    def self.shown(condition)
      operands = condition[:operands]
      return operands if condition[:operator] == '?:'

      operands.flat_map do |operand|
        next [operand] unless operand.key?(:arm)

        [operand[:body], leaving(operand)].compact
      end
    end

    # { leaves: return or raise, cells:, at: } for arm when its
    # code returns or raises, cells marking the paths that took
    # it, so left the method, at where its code is, so hovering it
    # lights the row; nil for an arm that does neither.
    def self.leaving(arm)
      word = arm[:text].to_s[LEAVES, 1]
      word && { leaves: word, cells: arm[:cells], at: arm[:at] }
    end

    # operands with each node standing for the nodes its kind
    # unfolds it into, eg a leaf with sites inside it for those
    # sites, then the leaf; a leaf or an arm for itself.
    def self.unfolded(operands)
      operands.flat_map do |operand|
        operator = operand[:operator]
        operator ? Kinds.of(operator).unfold(operand) : [operand]
      end
    end

    # A nested condition's row: its branch, its operator, or its
    # label when it has one, eg select { for a site inside a leaf,
    # and its value on each path.
    def self.subtree_row(condition, branch)
      text = condition.fetch(:label) { condition[:operator] }
      cells = FoldCells.values(condition[:cells])
      { kind: 'subtree', branch:, label: CodeTokens.label_code(text),
        at: condition[:at], cells: }
    end

    # One operand's row: its branch, text, coloured as the code it
    # is, written over more than one line read as one, each line
    # break and the indent around it one space, and its outcome on
    # each path.
    def self.operand_row(operand, branch)
      one_line = operand[:text].to_s.gsub(/\s*\n\s*/, ' ')
      { kind: 'operand', branch:, label: CodeTokens.code(one_line),
        at: operand[:at], cells: FoldCells.values(operand[:cells]) }
    end
  end
end
