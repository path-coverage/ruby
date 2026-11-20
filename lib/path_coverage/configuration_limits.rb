module PathCoverage
  # The settings of a PathCoverage.start block that limit a flow's
  # ways: the most paths a method may have and still be checked,
  # and whether a loop counts as a decision. It relies on its
  # includer's ConfigurationError, and sets @max_paths and @loops
  # from their defaults first.
  module ConfigurationLimits
    # The most paths a method may have and still be checked, by
    # default.
    MAX_PATHS = 4096
    # The most max_paths may be: 65536 paths keep analysing each
    # method's paths to about 2 seconds and 120 MB of JSON.
    PATHS_CAP = 65_536

    # Sets each limit to its default: a method with more than
    # MAX_PATHS paths fails, and no loop is a decision.
    def default_limits
      @max_paths = MAX_PATHS
      @loops = false
    end

    # The most paths a method may have and still be checked, as
    # max_paths sets it: one with more lists none of its ways, and
    # fails.
    def path_limit = @max_paths

    # Sets the most paths a method may have and still be checked;
    # refuses more than PATHS_CAP.
    def max_paths(count)
      if count > PATHS_CAP
        raise ConfigurationError, cap_refusal(count)
      end

      @max_paths = count
    end

    # Why max_paths refuses count.
    def cap_refusal(count)
      "max paths #{count} is more than #{PATHS_CAP}, the cap that " \
        "keeps analysing each method's paths to about 2 seconds " \
        'and 120 MB of JSON'
    end

    # True when each loop counts as a decision, 0 items or 1+.
    def loops? = @loops

    # Counts each loop as a decision: 0 items or 1+ items.
    def loops
      @loops = true
    end
  end
end
