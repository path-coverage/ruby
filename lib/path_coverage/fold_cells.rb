require_relative 'kinds'

module PathCoverage
  # The cells of a row of a decision's tree on a file's page, one per
  # path, as page data holds them. A cell says what its path did:
  # its text a letter, eg T or F, or empty with a mark the page
  # draws, eg a tick; with text to show on hover when its mark
  # alone may not say enough.
  module FoldCells
    # [text, mark, hover] of a leaf's or a condition's cell, by
    # the value it took on the path: a letter for each value
    # but a &. receiver's, which is a mark, present or absent,
    # hovering as not nil or nil.
    OUTCOMES = {
      true => ['T'], false => ['F'], nil => [''],
      ITEMS[0] => ['0'], ITEMS[1] => ['1'], ITEMS[2] => ['*'],
      ANSWERS[0] => ['T'], ANSWERS[1] => ['F'], ANSWERS[2] => ['TF'],
      PRESENCE[0] => ['', 'present', PRESENCE[0]],
      PRESENCE[1] => ['', 'absent', PRESENCE[1]]
    }.freeze

    # [text, mark] of a ternary's arm's cell: taken on a path
    # that took it, else blank.
    TAKEN = { true => ['', 'taken'], false => [''] }.freeze

    # [text, mark] of the cell of an arm that returns or raises:
    # leaves on a path that took it, so left the method there,
    # else blank.
    LEAVES = { true => ['', 'leaves'], false => [''] }.freeze

    # Example: true and false give ['T', nil, nil], ['F', nil, nil].
    # The cells of values, as page data holds them, each [text,
    # mark, hover] as names gives it, nil for a mark or hover it
    # has none of.
    def self.values(values, names = OUTCOMES)
      values.map do |value|
        text, mark, hover = names[value]
        [text, mark, hover]
      end
    end
  end
end
