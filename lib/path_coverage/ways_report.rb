require 'json'

module PathCoverage
  # A method flow's taken ways, and its loops' passes, as the JSON
  # report lists them: each way the steps one call, or one pass,
  # took, in order, a decision's {"at", "path"}, a loop's {"at",
  # "path", "passes"}, its path how many passes it made, or any
  # other row's {"at"}, with how many took it.
  module WaysReport
    # [{ "way" => [step, ...], "count" => n }] of walked, { way =>
    # n }, one unit's ways as a CallTrace counts them, in the order
    # first taken.
    def self.taken(walked)
      walked.map do |each, count|
        { 'way' => way(each), 'count' => count }
      end
    end

    # [step, ...] of steps, one way, as the JSON report lists it.
    def self.way(steps)
      steps.map { step(_1) }
    end

    # A step as the JSON report lists it: its row's at and, for a
    # decision's or a loop's, its path; for a loop's, the distinct
    # ways its passes took, ordered by their JSON text.
    def self.step(step)
      listed = { 'at' => at(step[0]) }
      return listed if step.size == 1

      listed['path'] = step[1]
      return listed if step.size == 2

      passes = step[2].map { way(_1) }.sort_by { JSON.generate(_1) }
      listed.merge('passes' => passes)
    end

    # { method's entry, or loop's name => { way => count } } of a
    # JSON report's flows, as a CallTrace counts them: each flow
    # listing its calls' ways and its loops' passes; a top flow
    # lists neither, as no call runs it.
    def self.ways(report)
      report['flows'].each_with_object({}) do |(entry, flow), found|
        next unless flow.key?('taken')

        found[entry] = read(entry, flow['taken'])
        flow['passes'].each do |at, passes|
          loop = named(entry, at)
          found[loop] = read(loop, passes)
        end
      end
    end

    # { way => count } of listed, the unit named unit's ways as
    # taken lists them.
    def self.read(unit, listed)
      listed.to_h do |each|
        [each['way'].map { unlisted(unit, _1) }, each['count']]
      end
    end

    # A step, as a JSON report lists it, of a unit named like
    # unit, as a CallTrace counts it.
    def self.unlisted(unit, step)
      name = named(unit, step['at'])
      return [name] unless step.key?('path')
      return [name, step['path']] unless step.key?('passes')

      ways = step['passes'].to_set do |way|
        way.map { unlisted(unit, _1) }
      end
      [name, step['path'], ways]
    end

    # The name, in the file of the unit named unit, of the row or
    # loop at, as at gives it: "k.rb:2:2" and "4:06" give
    # "k.rb:4:6".
    def self.named(unit, at)
      line, column = at.split(':')
      file = unit.split(':')[..-3].join(':')
      "#{file}:#{line}:#{Integer(column, 10)}"
    end

    # The line:column of the row or loop named name, the column two
    # digits, as a flow's rows have it: "k.rb:4:6" gives "4:06".
    def self.at(name)
      line, column = name.split(':').last(2)
      format('%<line>s:%<column>02d', line:, column: Integer(column))
    end
  end
end
