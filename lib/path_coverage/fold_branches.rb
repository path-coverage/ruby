module PathCoverage
  # The branches of a decision's tree on a file's page, joining each
  # operand's row to its operator's. A branch is a string of
  # kinds, one letter per cell: t a tee, l an ell, v a bar, h a
  # dash, s a space. The page draws each kind as lines a whole
  # row tall, so a branch joins the rows above and below it.
  module FoldBranches
    # The branch to an operand with more after it.
    TEE = 'ths'.freeze
    # The branch to the last operand.
    ELL = 'lhs'.freeze
    # The indent under an operand with more after it, its bar
    # running on down to them.
    BAR = 'vss'.freeze
    # The indent under the last operand.
    GAP = 'sss'.freeze
  end
end
