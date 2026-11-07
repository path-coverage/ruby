require 'json'
require_relative 'kinds'
require_relative 'measured_by'
require_relative 'merge'

module PathCoverage
  # Reads back the JSON reports JsonWriter writes, merging the
  # counts of several runs, and refusing any report whose
  # decisions' paths are listed differently from a render's.
  module JsonReader
    # The keys of a JSON report's fingerprint.
    FINGERPRINT = %w[ignored treats].freeze

    # The operands of the JSON reports at paths, merged; raises
    # unless each measured the kinds a render does, with
    # fingerprint, as Configuration#fingerprint gives it.
    def self.operands(paths, fingerprint)
      Merge.operands(paths.map { |path| read(path, fingerprint) })
    end

    # The paths taken of the JSON reports at paths, as
    # Render.run takes them: decision_paths:, each decision's possible
    # paths, outside:, those a treatment rules out, and reached:,
    # each statement's reaches, each merged.
    def self.taken(paths)
      decision_paths = Merge.paths(paths.map do |path|
        paths_of(path)
      end)
      outside = merged(paths, 'outside')
      { decision_paths:, outside:, reached: reached(paths) }
    end

    # Example: { "k.rb:2:2" => 2 } and { "k.rb:2:2" => 1 } give
    # { "k.rb:2:2" => 3 }.
    # The reaches of the JSON reports at paths, each statement's
    # summed; nil when none has any, eg reports the :post reporter
    # sent, so a render cannot say what was reached.
    def self.reached(paths)
      reports = paths.map { |path| JSON.parse(File.read(path)) }
      runs = reports.map { |report| report['reached'] }.compact
      return nil if runs.empty?

      runs.reduce { |all, run| all.merge(run) { |_, a, b| a + b } }
    end

    # Raises unless json, the JSON report at path, measured the
    # kinds a render does, with fingerprint, and was measured by
    # the same tools at the same versions; one that differs in
    # either, or names none, can list its decisions' paths
    # differently, so its counts cannot be trusted to the paths a
    # render lists.
    def self.same_measuring(path, json, fingerprint)
      kinds = json['kinds'] == Kinds.names
      unless kinds && json.slice(*FINGERPRINT) == fingerprint
        raise ArgumentError, "#{path} measured other kinds"
      end
      return if json['measured_by'] == MeasuredBy.versions

      raise ArgumentError, "#{path} was measured by other tools"
    end

    # The key lists of the JSON reports at paths, as listed_of
    # gives them, each path's count the sum of every report's.
    def self.merged(paths, key)
      Merge.listed(paths.map { |path| listed_of(path, key) })
    end

    # The JSON report at path's list under key, eg its paths a
    # treatment rules out, { decision => { path => count } }; none
    # for a report that has none, so the render claims none.
    def self.listed_of(path, key)
      json = JSON.parse(File.read(path))
      json.fetch(key, {}).transform_values do |taken|
        taken.to_h { |each| [each['path'], each['count']] }
      end
    end

    # The decision paths of the JSON report at path, as
    # Result#paths gives them; none for a report that has none.
    def self.paths_of(path)
      json = JSON.parse(File.read(path))
      json.fetch('paths', {}).transform_values do |decision|
        decision['taken'].map do |each|
          { path: each['path'], count: each['count'] }
        end
      end
    end

    # The operands of the JSON report at path, which raises
    # unless it measured the kinds a render does, with
    # fingerprint.
    def self.read(path, fingerprint)
      json = JSON.parse(File.read(path))
      same_measuring(path, json, fingerprint)
      json['decisions'].transform_values do |leaves|
        leaves.map { |leaf| counts(leaf) }
      end
    end

    # One operand's counts as JSON holds them, with the keys,
    # and any only: value, as the symbols Result#operands uses.
    def self.counts(leaf)
      counts = { truthy: leaf['truthy'], falsy: leaf['falsy'] }
      only = leaf['only']
      only ? counts.merge(only: only.to_sym) : counts
    end
  end
end
