require_relative 'condition'

module PathCoverage
  # The way one call is taking through its method, kept as a stack
  # of units: the call's own, then each loop under way, innermost
  # last. A step goes to the innermost loop holding its row,
  # closing first any loop under way that does not hold it. Each
  # pass of a loop is a way of its own, counted under the loop;
  # the unit holding the loop takes it as one step: how many
  # passes it made, 0, 1 or 2+, and the set of ways they took. So
  # a way holds each row at most once, however many passes a loop
  # makes.
  class Walk
    # A call, or a loop under way, named by its entry or its loop,
    # with the steps of its way so far, or of its latest pass, how
    # many passes it has made, and the distinct ways of those ended.
    Unit = Struct.new(:name, :steps, :passes, :seen)

    # A call of the method whose entry is named entry, just
    # entered, counting each way it ends on ways, { unit's name =>
    # { way => count } }; loops is { row's name => the names of
    # the loops holding it, outermost first }, and repeats { row's
    # name => the while or until whose test holds it }.
    def initialize(entry, ways, loops, repeats = {})
      @ways = ways
      @loops = loops
      @repeats = repeats
      @units = [unit(entry)]
    end

    # The name of the entry of the method being called.
    def entry = @units.first.name

    # Adds step, a row's [name, ...], to the way of the innermost
    # loop under way holding its row, or the call's own; but no
    # step of a row in the test of a while under way, as each test
    # after its first repeats its first.
    def step(step)
      name = step[0]
      return if @units.map(&:name).include?(@repeats[name])

      close_to(@loops[name])
      @units.last.steps << step
    end

    # Starts a pass of the loop named loop, counting its pass
    # before when there is one.
    def passed(loop)
      opened = opened(loop)
      if opened.passes.positive?
        count(opened)
        opened.steps = []
      end
      opened.passes += 1
    end

    # Ends the loop named loop, its items all given.
    def exhausted(loop)
      opened(loop)
      close
    end

    # Ends the call, closing every loop under way, and counts its
    # way.
    def finish
      close_to([])
      count(@units.first)
    end

    private

    # A unit named name, with no step or pass yet.
    def unit(name) = Unit.new(name, [], 0, Set.new)

    # The unit of the loop named loop, innermost, any loop under
    # way inside it closed; a new one when it is not under way.
    def opened(loop)
      close_to([*@loops[loop], loop])
      @units << unit(loop) unless @units.last.name == loop
      @units.last
    end

    # Closes each loop under way, innermost first, until one of
    # holding, the loops holding a row, is innermost.
    def close_to(holding)
      close while @units.size > 1 && holding.none?(@units.last.name)
    end

    # Ends the innermost loop under way: counts its last pass, if
    # it made one, and adds it to the way holding it as one step.
    def close
      ended = @units.pop
      count(ended) if ended.passes.positive?
      items = ITEMS[[ended.passes, 2].min]
      @units.last.steps << [ended.name, [items], ended.seen]
    end

    # Counts unit's steps as one more taking of its way, noting it
    # among the ways seen.
    def count(unit)
      way = unit.steps.dup.freeze
      (@ways[unit.name] ||= Hash.new(0))[way] += 1
      unit.seen << way
    end
  end
end
