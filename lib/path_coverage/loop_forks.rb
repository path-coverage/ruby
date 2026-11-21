require 'prism'
require_relative 'decision'
require_relative 'loop_nodes'

module PathCoverage
  # The loops of each method that fork when loops are decisions:
  # 0 items, or 1+ items, its body walked once. Each is one whose
  # passes a pass call put first in its body can show, so a
  # call's trace tells the two apart, a block method's block,
  # eg any?'s, among them.
  module LoopForks
    # { def decision => { loop's name => [its bytes, its body's] } }
    # of each def in source, at path.
    def self.of(source, path)
      LoopNodes.defs(Prism.parse(source).value).to_h do |node|
        [Decision.of(path, node), in_def(node, path)]
      end
    end

    # { loop's name => [its bytes, its body's] } of each loop of
    # node, a def, at path, that forks.
    def self.in_def(node, path)
      loops = LoopNodes.loops_in(node.body)
      loops.filter_map { fork(_1, path) }.to_h
    end

    # [name, [its bytes, its body's]] of loop, at path, when a
    # pass call can go first in its body; else nil.
    def self.fork(loop, path)
      body = LoopNodes.body_of(loop)
      return if body.nil? || LoopNodes.modifier?(loop)
      return unless LoopNodes.first_statement(body)

      [Decision.at(path, LoopNodes.at(loop)),
       [range(loop.location), range(body.location)]]
    end

    # The bytes of location, as a range.
    def self.range(location)
      location.start_offset...location.end_offset
    end
  end
end
