require_relative 'condition'
require_relative 'kinds/block'
require_relative 'kinds/case'
require_relative 'kinds/chain'
require_relative 'kinds/choice'
require_relative 'kinds/contains'
require_relative 'kinds/safe'
require_relative 'kinds/write'

module PathCoverage
  # The kinds of condition, each a module that knows, for a
  # condition named by one of its OPERATORS, the ways it can be
  # evaluated, its value in each column of its decision's tree, and
  # the inserts that instrument it. Each extends Kinds::Base,
  # whose hooks give what most kinds need.
  module Kinds
    # Every kind, each named by its operators.
    ALL = [Block, Case, Chain, Choice, Contains, Safe, Write].freeze

    # { operator => kind } for every operator of every kind.
    BY_OPERATOR = ALL.flat_map do |kind|
      kind::OPERATORS.map { |operator| [operator, kind] }
    end.to_h.freeze

    # The kind of a condition named operator, eg Chain for &&.
    def self.of(operator)
      BY_OPERATOR.fetch(operator)
    end

    # The names of the kinds measured, eg chain for Chain: a
    # report's fingerprint, as runs measuring different kinds
    # list a decision's paths differently.
    def self.names
      ALL.map { |kind| kind.name.split('::').last.downcase }
    end
  end
end
