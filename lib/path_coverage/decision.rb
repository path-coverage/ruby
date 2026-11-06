module PathCoverage
  # Names a condition by where it starts in its file, so the
  # rewriter and the manifest agree on which decision is which.
  module Decision
    # "path:line:column" of node, eg "k.rb:2:2".
    def self.of(path, node)
      at(path, node.location)
    end

    # "path:line:column" of where loc starts, eg an if's keyword,
    # which a modifier if's statement comes before.
    def self.at(path, loc)
      "#{path}:#{loc.start_line}:#{loc.start_column}"
    end
  end
end
