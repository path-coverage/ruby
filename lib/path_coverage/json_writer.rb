require 'json'
require_relative 'kinds'

module PathCoverage
  # The base reporter: the result as raw JSON, which every
  # other reporter can read back.
  module JsonWriter
    # Writes operands, as Result gives them, paths, as
    # PathsReport gives them, and totals, as JsonReports.totals
    # gives them, to path as {"decisions": {decision: [counts, ...]},
    # "paths": {decision: {leaves:, taken:}}, "totals": {"alone":
    # [taken, possible]}}.
    # parts are json's.
    def self.write(operands, path, paths = {}, **parts)
      File.write(path, json(operands, paths, **parts))
    end

    # The keys of parts listed as { decision => [{path:, count:}] }:
    # each path taken that a treatment rules out, as
    # Result#outside gives them.
    LISTED = %i[outside].freeze

    # operands, and any paths, and parts' outside:, totals:,
    # cards:, as WithinMethods.listed gives them, and tree:, as
    # WithinMethods.tree gives it, as the JSON report's text, with
    # parts' fingerprint:, as Configuration#fingerprint gives
    # it, the names of the kinds measured, and parts' reached:,
    # as Recorder#reached gives it, even empty, as a run that
    # reached no statement says so; none when not given.
    def self.json(operands, paths = {}, **parts)
      fingerprint = parts.fetch(:fingerprint, {})
      report = { 'decisions' => operands, **fingerprint }
      report['paths'] = paths unless paths.empty?
      report.merge!(lists(parts))
      report['reached'] = parts[:reached] if parts.key?(:reached)
      report.merge!(kept(parts))
      report['kinds'] = Kinds.names
      JSON.pretty_generate(report)
    end

    # The keys of parts written as they are, when not empty.
    KEPT = %i[totals cards tree].freeze

    # { key => its value } of each of parts' KEPT keys that has
    # a value not empty.
    def self.kept(parts)
      KEPT.filter_map do |key|
        value = parts.fetch(key, {})
        [key.to_s, value] unless value.empty?
      end.to_h
    end

    # { key => its list } of each of parts' LISTED keys that
    # has one, as listed gives them.
    def self.lists(parts)
      LISTED.filter_map do |key|
        taken = parts.fetch(key, {})
        [key.to_s, listed(taken)] unless taken.empty?
      end.to_h
    end

    # taken, { decision => { path => count } }, as JSON lists it,
    # eg { 'k.rb:2:2' => [{ path: [true, false], count: 1 }] }.
    def self.listed(taken)
      taken.transform_values do |counts|
        counts.map { |path, count| { path:, count: } }
      end
    end
  end
end
