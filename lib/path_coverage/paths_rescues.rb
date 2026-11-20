module PathCoverage
  # How a begin with a rescue forks its flow. PathsWays includes
  # it. The begin is a scope. Its body either completes, or a
  # rescue runs. A rescue can run after any prefix of a way through
  # the body, because a raise can come from anywhere. A prefix can
  # end at any row, including one inside an arm or a loop's body.
  module PathsRescues
    # { key => its rescues } of each rescue fork of rescues, as
    # RescueForks gives them.
    def self.counts(rescues)
      rescues.to_h do |name, (count, *)|
        [PathsTree.key_at(name), count]
      end
    end

    # The regions of each rescue fork of rescues, as RescueForks
    # gives them. Its body is run on its path 0. The body of its
    # rescue numbered n is run on its path n.
    def self.regions(rescues)
      rescues.flat_map do |name, (_, _, body, clauses)|
        owner = PathsTree.key_at(name)
        bodies = [['body', body], *clauses.map { ['rescue', _1] }]
        bodies.each_with_index.map do |(arm, range), path|
          PathsTree::Region.new(owner:, range:, arm:, on: [path],
                                leaf: nil, leaves: nil)
        end
      end
    end

    # The parts of the rescue fork keyed key, [on, returned, raised,
    # passed]. Its body's ways that go on complete, labelled [key,
    # 0]. A prefix of the body, or a way that raises in it, then
    # runs rescue n, labelled [key, n], then that rescue's rows. A
    # raise written in the body is taken as caught there. Ways that
    # return or pass still leave.
    def rescue_pair(key)
      on, returned, _, passed = body = run_on(key, 0)
      completed = [@ways.times(on, @ways.unit([key, 0])), returned,
                   @ways.zero, passed]
      ran = (1..@rescues.fetch(key)).map do |path|
        prefix = rescue_prefix(key, body, path)
        run_on(key, path).map { @ways.times(prefix, _1) }
      end
      added([completed, *ran])
    end

    # The ways up to and including the step of the rescue numbered
    # path of the fork keyed key. They start with each prefix of
    # its body, or with one of body, its parts, that goes through
    # the whole of it or raises in it.
    def rescue_prefix(key, (on, _, raised, _), path)
      whole = @ways.plus(on, raised)
      ended = @ways.plus(opened(running(key, 0)), whole)
      @ways.times(ended, @ways.unit([key, path]))
    end

    # The parts of the rows the fork keyed key runs on its path at
    # index path, one after another: its body on path 0, else the
    # body of its rescue numbered path.
    def run_on(key, path)
      sequence(running(key, path).map { pair_of(_1) })
    end

    # The ways that stop partway through the rows keyed keys,
    # before the last of them completes. Each goes on through the
    # rows before one row, then stops before that row or inside
    # it. outcomes is the parent's path's outcomes, or nil at the
    # top. Only a row's paths that fit outcomes are taken.
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
    # step. For a decision, each fitting path's step, then a stop
    # partway through the rows its arm runs. For a loop, a stop
    # partway through its body. A return or a raise has none,
    # because it leaves.
    def inside(key, outcomes)
      return rescue_inside(key) if @rescues.key?(key)
      return looped(key) unless @rows.key?(key)

      decision = @rows[key].decision
      return @ways.zero if decision.nil?

      cuts = each_fitting(key, outcomes, @ways.zero) do |path|
        inside_on(key, path)
      end
      cuts.reduce(@ways.zero) { |all, cut| @ways.plus(all, cut) }
    end

    # The ways that stop inside the decision row keyed key, on its
    # path at index path. The path's step comes with the whole of
    # the decisions in its condition. No cut divides those. Then
    # comes a stop partway through the rows its arms run.
    def inside_on(key, path)
      outcomes = possible(@rows[key].decision)[path]
      by = running(key, path).group_by { @places[_1]['leaf'].nil? }
      whole = whole_on(key, path, outcomes, by.fetch(false, []))
      @ways.times(whole, opened(by.fetch(true, []), outcomes))
    end

    # The ways through the decision row keyed key on its path at
    # index path. They include the whole of leaves, the rows in its
    # condition, one after another.
    def whole_on(key, path, outcomes, leaves)
      pairs = leaves.map { fitted_pair(_1, outcomes) }
      @ways.times(own(key, path, outcomes), sequence(pairs)[0])
    end

    # The ways that stop inside the loop keyed key, partway through
    # its body. When loops fork, they start with its step of at
    # least one item.
    def looped(key)
      partway = opened(running(key, 1))
      return partway unless @forking

      @ways.times(@ways.unit([key, 1]), partway)
    end

    # The ways that stop inside the rescue fork keyed key. They stop
    # partway through its body, or partway through the rows of one
    # of its rescues, after that rescue's step.
    def rescue_inside(key)
      body = run_on(key, 0)
      ran = (1..@rescues.fetch(key)).map do |path|
        prefix = rescue_prefix(key, body, path)
        @ways.times(prefix, opened(running(key, path)))
      end
      ran.reduce(opened(running(key, 0))) do |all, cut|
        @ways.plus(all, cut)
      end
    end

    # The parts of the row keyed key. outcomes is its parent's
    # path's outcomes, or nil at the top.
    def fitted_pair(key, outcomes)
      outcomes.nil? ? pair_of(key) : child_pair(key, outcomes)
    end
  end
end
