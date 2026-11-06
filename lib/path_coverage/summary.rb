require_relative 'configuration'

module PathCoverage
  # Which file a decision is in, and whether a file is in a group.
  module Summary
    # True when path matches any of globs.
    def self.matches?(path, globs)
      globs.any? do |glob|
        File.fnmatch?(glob, path, Configuration::GLOB_FLAGS)
      end
    end

    # The file a decision is in: its name minus :line:column.
    def self.path_of(decision)
      decision.sub(/:\d+:\d+\z/, '')
    end
  end
end
