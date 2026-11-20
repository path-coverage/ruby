module PathCoverage
  # Which paths of a decision row fit the path its parent takes.
  # CardWays includes it. A row that is the whole of its parent's
  # leaf runs only the paths that give that leaf the outcome its
  # parent's path has.
  module CardFitting
    # The block's value on each path of the decision row keyed
    # key, by index. A path that does not fit outcomes gets none
    # instead. fits_of decides which paths fit.
    def each_fitting(key, outcomes, none)
      fits = fits_of(key, outcomes)
      possible(@rows[key].decision).each_index.map do |path|
        fits.call(path) ? yield(path) : none
      end
    end

    # A test of whether a path index of the decision row keyed key
    # fits outcomes, its parent's path's. At the top outcomes is
    # nil, and every path fits. Every path fits a row that gives
    # nothing too. Otherwise a path fits when it gives its leaf the
    # outcome the parent's path has, or gives what is not known.
    def fits_of(key, outcomes)
      place = @places[key]
      gives = place['gives']
      return ->(_) { true } if outcomes.nil? || gives.nil?

      fits = [nil, outcomes[place['leaf']]]
      ->(path) { fits.include?(gives[path]) }
    end
  end
end
