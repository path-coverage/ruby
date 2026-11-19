require_relative 'walk'

module PathCoverage
  # The ways each call of a covered method takes: a stack of the
  # calls under way in each thread, each with the way its method
  # is taking, a step going to the innermost call of the method
  # holding its row.
  class CallTrace
    # Starts with no method known and no way taken.
    def initialize
      @entries = {}
      @repeats = {}
      @owners = {}
      @ways = {}
      @stack_key = :"path_coverage_calls_#{object_id}"
    end

    # { unit's name => { way => count } } of every way ended so
    # far, as Walk counts them.
    attr_reader :ways

    # Notes the method whose entry is named entry, loops being
    # { its row's name => the names of the loops holding it,
    # outermost first }, and repeats { its row's name => the while
    # or until whose test holds it }, as Walk takes them.
    def know(entry, loops, repeats = {})
      @entries[entry] = loops
      @repeats[entry] = repeats
      loops.each_key { |row| @owners[row] = entry }
    end

    # Starts a call of a covered method, its method known once it
    # reaches its entry.
    def call
      stack.push(nil)
    end

    # Notes the statement named name reached: a method's entry
    # starts its call's way, unless no call is under way to take
    # it, as when the call began before this trace did; any other
    # row is a step of the innermost call of the method holding it.
    def reach(name)
      if @entries.key?(name)
        enter(name) unless stack.empty?
      else
        innermost(@owners[name])&.step([name])
      end
    end

    # Notes the decision named decision taking path, a step of the
    # innermost call of the method holding it.
    def decided(decision, path)
      innermost(@owners[decision])&.step([decision, path])
    end

    # Notes a pass of the loop named loop, a block called with one
    # more item, in the innermost call of the method holding it.
    def pass(loop)
      innermost(@owners[loop])&.passed(loop)
    end

    # Ends the innermost call under way, counting its way.
    def return
      stack.pop&.finish
    end

    private

    # Starts the way of the innermost call under way, of the
    # method whose entry is named entry.
    def enter(entry)
      stack[-1] = Walk.new(entry, @ways, @entries[entry],
                           @repeats[entry])
    end

    # The calls under way in the current thread, innermost last,
    # each the Walk of its way, or nil before it reaches its entry.
    def stack
      Thread.current[@stack_key] ||= []
    end

    # The Walk of the innermost call under way of the method
    # whose entry is named entry, else nil.
    def innermost(entry)
      stack.reverse_each.find { |walk| walk&.entry == entry }
    end
  end
end
