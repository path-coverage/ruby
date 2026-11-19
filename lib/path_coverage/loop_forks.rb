require 'prism'
require_relative 'condition'
require_relative 'decision'
require_relative 'loop_nodes'

module PathCoverage
  # The loops of each method that fork when loops are decisions:
  # 0 items, or 1+ items, its body walked once. Each is one whose
  # passes a pass call put first in its body can show, so a
  # call's trace tells the two apart; but no block of a block
  # method's decision, eg any?'s, whose paths count its items
  # already.
  module LoopForks
    # { def decision => { loop's name => [its bytes, its body's] } }
    # of each def in source, at path, decisions as
    # Manifest.decisions gives them.
    def self.of(source, path, decisions)
      blocks = decision_blocks(decisions)
      LoopNodes.defs(Prism.parse(source).value).to_h do |node|
        [Decision.of(path, node), in_def(node, path, blocks)]
      end
    end

    # { loop's name => [its bytes, its body's] } of each loop of
    # node, a def, at path, that forks, blocks being where the
    # block of each block method's decision ends.
    def self.in_def(node, path, blocks)
      loops = LoopNodes.loops_in(node.body)
      loops.filter_map { fork(_1, path, blocks) }.to_h
    end

    # Where the block of each block method's decision among
    # decisions ends, a byte offset, as its call does.
    def self.decision_blocks(decisions)
      by = decisions.values.group_by { BLOCK_PATHS.key?(_1.operator) }
      by.fetch(true, []).to_set { _1.extent.end }
    end

    # [name, [its bytes, its body's]] of loop, at path, when it is
    # no block method's, its call not ending at one of blocks, and
    # a pass call can go first in its body; else nil.
    def self.fork(loop, path, blocks)
      body = LoopNodes.body_of(loop)
      return if blocks.include?(loop.location.end_offset)
      return if body.nil? || LoopNodes.modifier?(loop)
      return unless LoopNodes.first_statement(body)

      [Decision.at(path, loop.location),
       [range(loop.location), range(body.location)]]
    end

    # The bytes of location, as a range.
    def self.range(location)
      location.start_offset...location.end_offset
    end
  end
end
