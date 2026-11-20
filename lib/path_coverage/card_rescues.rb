module PathCoverage
  # How a def's rescue forks its card, for CardWays, which
  # includes it: the body completes, or its rescue runs, having
  # run any prefix of a way of the body first, cut at any of its
  # rows, inside an arm or a loop's body too, as a raise there can
  # come from anywhere.
  module CardRescues
    # triple, the card's ways [on, returned, raised], forked by its
    # rescues when it has any: going on, those completing, labelled
    # [its key, 0], or, after any prefix of the body, those raising
    # in it among them, as a raise written there is taken as caught
    # there, running its rescue numbered n, labelled [its key, n];
    # those returning still leave.
    def rescued(triple)
      return triple if @rescues.empty?

      on, returned, raised = triple
      name, count = @rescues.first
      key = CardTree.key_at(name)
      completed = @ways.times(on, @ways.unit([key, 0]))
      ran = ran(key, count, @ways.plus(on, raised))
      [@ways.plus(completed, ran), returned, @ways.zero]
    end

    # The ways that run one of the count rescues of the fork keyed
    # key: after any prefix of the body, ended, the ways going on
    # through all of it or raising in it, among them, that rescue.
    def ran(key, count, ended)
      prefixes = @ways.plus(opened(@children.fetch(nil, [])), ended)
      runs = (1..count).map { @ways.unit([key, _1]) }
      either = runs.reduce { |all, run| @ways.plus(all, run) }
      @ways.times(prefixes, either)
    end

    # The ways that stop partway through the rows keyed keys, one
    # after another, before the last of them completes: going on
    # through those before one, then stopping before it or inside
    # it. Each row's paths are those that fit outcomes, its
    # parent's path's, when given; nil at the top.
    def opened(keys, outcomes = nil)
      on = @ways.one
      keys.reduce(@ways.zero) do |cut, key|
        stop = @ways.plus(@ways.one, inside(key, outcomes))
        here = @ways.times(on, stop)
        on = @ways.times(on, fitted_pair(key, outcomes)[0])
        @ways.plus(cut, here)
      end
    end

    # The ways that stop inside the row keyed key, after its own
    # step: on each of its paths that fits outcomes, that step,
    # then stopping partway through the rows its arm runs. A
    # loop's, at least one item then partway through its body; a
    # return's or raise's, none, as it leaves.
    def inside(key, outcomes)
      return looped(key) unless @rows.key?(key)

      decision = @rows[key].decision
      return @ways.zero if decision.nil?

      cuts = each_fitting(key, outcomes, @ways.zero) do |path|
        inside_on(key, path)
      end
      cuts.reduce(@ways.zero) { |all, cut| @ways.plus(all, cut) }
    end

    # The ways that stop inside the decision row keyed key on its
    # path at index path: that path's step with the whole of the
    # rows in its leaves, the decisions of its condition, which no
    # cut divides, then partway through the rows its arms run.
    def inside_on(key, path)
      outcomes = possible(@rows[key].decision)[path]
      by = running(key, path).group_by { @places[_1]['leaf'].nil? }
      whole = whole_on(key, path, outcomes, by.fetch(false, []))
      @ways.times(whole, opened(by.fetch(true, []), outcomes))
    end

    # The ways through the decision row keyed key on its path at
    # index path, with outcomes, and the whole of the rows leaves,
    # those in its leaves, one after another.
    def whole_on(key, path, outcomes, leaves)
      pairs = leaves.map { fitted_pair(_1, outcomes) }
      @ways.times(own(key, path, outcomes), sequence(pairs)[0])
    end

    # The ways that stop inside the loop keyed key: at least one
    # item, then partway through its body.
    def looped(key)
      @ways.times(@ways.unit([key, 1]), opened(running(key, 1)))
    end

    # The pair of the row keyed key, its parent's path having
    # outcomes, nil at the top, as child_pair gives it.
    def fitted_pair(key, outcomes)
      outcomes.nil? ? pair_of(key) : child_pair(key, outcomes)
    end
  end
end
