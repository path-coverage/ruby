require_relative 'method_ways'
require_relative 'ways_report'

module PathCoverage
  # The ways a method's card lists for the JSON report: those its
  # calls took, its loops' passes, and of the ways one call can take,
  # those some call took, covered, and those none did, gaps.
  module CardWayLists
    # { "taken", "passes" } of the method whose entry is named
    # entry: the ways its calls took, ways being { unit's name =>
    # { way => count } }, as a CallTrace counts them; and the passes
    # of each of loops, the names of the method's loops.
    def self.walked(entry, ways, loops)
      { 'taken' => WaysReport.taken(ways.fetch(entry, {})),
        'passes' => passes(ways, loops) }
    end

    # { "covered", "gaps", "impossible", "impossible_taken" } of
    # the method whose entry is named entry, ways as walked has
    # them; checked [split, forked]: split [possible, impossible],
    # the ways one call can take, and those none can, as
    # MethodWays.split_card lists them, forked the names of the
    # loops that fork there.
    def self.checked(entry, ways, ((possible, impossible), forked))
      seen = witnessed(ways.fetch(entry, {}), forked)
      { 'covered' => covered(possible, seen),
        'gaps' => listed(split(possible, seen).last),
        'impossible' => listed(impossible),
        'impossible_taken' => listed(split(impossible, seen).first) }
    end

    # [taken, untaken] of ways: those some call witnessed, as seen
    # counts them, and those none did.
    def self.split(ways, seen)
      by = ways.group_by { seen.key?(MethodWays.matched(_1)) }
      [by.fetch(true, []), by.fetch(false, [])]
    end

    # Each of ways as the JSON report lists a way.
    def self.listed(ways)
      ways.map { WaysReport.way(_1) }
    end

    # { loop's at => its passes' ways, as WaysReport.taken lists
    #   them } of each of loops, ways as of has them.
    def self.passes(ways, loops)
      loops.to_h do |loop|
        [WaysReport.at(loop), WaysReport.taken(ways.fetch(loop, {}))]
      end
    end

    # { way => how many calls witnessed it } of walked, { way =>
    # count }, each way's steps ordered, as MethodWays.witnessed
    # gives them, each loop of forked a fork.
    def self.witnessed(walked, forked)
      walked.each_with_object(Hash.new(0)) do |(way, count), seen|
        MethodWays.witnessed(way, forked).each { seen[_1] += count }
      end
    end

    # [{ "way", "count" }] of each of possible some call took, as
    # seen counts them.
    def self.covered(possible, seen)
      possible.filter_map do |way|
        count = seen.fetch(MethodWays.matched(way), 0)
        next unless count.positive?

        { 'way' => WaysReport.way(way), 'count' => count }
      end
    end
  end
end
