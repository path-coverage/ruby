module PathCoverage
  # Which paths of a decision row fit the path its parent takes,
  # for CardWays, which includes it: a row that is the whole of
  # its parent's leaf runs only the paths giving that leaf the
  # outcome its parent's path has.
  module CardFitting
    # The block's value on each path of the decision row keyed key,
    # by index, or none on a path that does not fit outcomes, its
    # parent's path's, as fits_of tests it.
    def each_fitting(key, outcomes, none)
      fits = fits_of(key, outcomes)
      possible(@rows[key].decision).each_index.map do |path|
        fits.call(path) ? yield(path) : none
      end
    end

    # A test of whether each path index of the decision row keyed
    # key fits outcomes, its parent's path's: every path fits at
    # the top, outcomes being nil, or for a row that gives nothing;
    # else those that give its leaf the outcome that path has, or
    # that give what is not known.
    def fits_of(key, outcomes)
      place = @places[key]
      gives = place['gives']
      return ->(_) { true } if outcomes.nil? || gives.nil?

      fits = [nil, outcomes[place['leaf']]]
      ->(path) { fits.include?(gives[path]) }
    end
  end
end
