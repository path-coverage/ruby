require_relative 'kinds'

module PathCoverage
  # The settings of a PathCoverage.start block that change which
  # paths a decision has: ignore, eg ignore '&&=', and treat, eg
  # treat 'name', as: :present. It relies on its includer's
  # @ignored, @treats and check.
  module ConfigurationPaths
    TREATMENTS = %w[present nonempty].freeze

    # The operators whose decisions are not measured, chosen with
    # ignore, eg ['&&=']; none when nothing was chosen.
    attr_reader :ignored

    # Chooses operators whose decisions are not measured, eg
    # ignore '&&=' measures no &&= write; a decision inside one, eg
    # on its right side, still is. Refuses an operator there
    # is no kind of decision for.
    def ignore(*operators)
      check('operator', operators, Kinds::BY_OPERATOR.keys)
      @ignored = operators
    end

    # Treats calls to the method named name as never nil, with
    # as: :present, so a &. after such a call has no nil path;
    # or as true exactly when its receiver has items, with as:
    # :nonempty, eg any?. It applies in each covered file
    # matching glob, relative to root, or in every one with no
    # glob. Refuses any other treatment.
    def treat(name, as:, in: nil)
      check('treatment', [as], TREATMENTS)
      @treats << [name, as.to_s, binding.local_variable_get(:in)]
    end

    # The names of the methods treated as as, eg 'present', in
    # the covered file at relative_path.
    def treated(as, relative_path)
      flags = Configuration::GLOB_FLAGS
      @treats.filter_map do |name, treatment, glob|
        next unless treatment == as

        name if glob.nil? || File.fnmatch?(glob, relative_path, flags)
      end
    end

    # The settings that change which paths a decision has, eg
    # { 'ignored' => ['&&='],
    #   'treats' => [['name', 'present', nil]] },
    # each only when set: runs whose fingerprints differ list
    # their decisions' paths differently.
    def fingerprint
      print = {}
      print['ignored'] = @ignored unless @ignored.empty?
      print['treats'] = @treats unless @treats.empty?
      print
    end
  end
end
