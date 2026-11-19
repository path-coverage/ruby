require_relative 'calls'
require_relative 'configuration'
require_relative 'manifest'
require_relative 'method_loops'
require_relative 'recorder'
require_relative 'render'
require_relative 'result'
require_relative 'rewriter'
require_relative 'within_methods'

# Path coverage for Ruby. This file is the kernel: it loads
# before any covered file and is never itself instrumented, since
# an instrumented recorder would record itself.
module PathCoverage
  @recorder = Recorder.new
  @config = nil
  # { full path => {source:, decisions:} } of each covered file
  # parsed as it loaded, so the exit report need not read it
  # again.
  @parsed = {}

  # The recorder of the latest start, that every instrumented
  # operand reports to.
  def self.recorder
    @recorder
  end

  # The configuration of the latest start, which the load
  # hook consults; nil before the first start.
  def self.config
    @config
  end

  # Instruments every file later required that the settings
  # block covers, and reports when the process exits. on_exit
  # is Kernel#at_exit except in tests, which must not print
  # a report as their own process exits. Each start records
  # afresh, so a later start, as a later test makes, never
  # counts an earlier one's evaluations.
  def self.start(on_exit: method(:at_exit), &)
    config = Configuration.new(&)
    @recorder = Recorder.new
    install_hook if @config.nil?
    @config = config
    on_exit.call { report(config) }
  end

  # Starts from settings in env alone, for a run whose code
  # cannot be changed, eg one started by RUBYOPT=-r: covers
  # the comma-separated PATH_COVERAGE_COVER globs under
  # PATH_COVERAGE_ROOT, skipping any matching the
  # comma-separated PATH_COVERAGE_SKIP globs, writing the JSON
  # report into PATH_COVERAGE_DIR and POSTing it to
  # PATH_COVERAGE_COLLECTOR. Without a collector it
  # starts nothing, so RUBYOPT can be set for every run.
  def self.start_from_env(env, on_exit: method(:at_exit))
    return unless env.key?('PATH_COVERAGE_COLLECTOR')

    start(on_exit:, &env_settings(env))
  end

  # The start block of the settings in env, as start_from_env
  # reads them.
  def self.env_settings(env)
    covers = env.fetch('PATH_COVERAGE_COVER').split(',')
    skips = env.fetch('PATH_COVERAGE_SKIP', '').split(',')
    proc do
      root env.fetch('PATH_COVERAGE_ROOT')
      covers.each { |glob| cover glob }
      skips.each { |glob| skip glob }
      coverage_dir env.fetch('PATH_COVERAGE_DIR')
      collector env.fetch('PATH_COVERAGE_COLLECTOR')
      report :post
    end
  end

  # Routes every later load through instrumented, under
  # whichever configuration is current. Installed once: a
  # second definition would warn that it was redefined.
  def self.install_hook
    iseq = RubyVM::InstructionSequence
    iseq.singleton_class.define_method(:load_iseq) do |path|
      PathCoverage.instrumented(path, PathCoverage.config)
    end
  end

  # The compiled, rewritten code of path, or nil for a path
  # config does not cover, which Ruby then loads as normal. Each
  # call of a method in it is traced, as its way is recorded.
  def self.instrumented(path, config)
    return unless config.covers?(path)

    parsed = @parsed[path] = Manifest.parse(path, config)
    args = [parsed[:source], config.relative(path),
            parsed[:decisions]]
    loops = MethodLoops.of(*args)
    rewritten = rewritten(path, parsed, config, loops)
    iseq = RubyVM::InstructionSequence
    traced(iseq.compile(rewritten, path, path),
           [loops, MethodLoops.repeats(*args)])
  end

  # The source of parsed, the file at path, rewritten: each of its
  # decisions recorded, each statement reach counted, and each
  # pass of each of loops, { entry => loops }, noted.
  def self.rewritten(path, parsed, config, loops)
    source = parsed[:source]
    reaches = WithinMethods.reaches(path, parsed, config)
    passes = MethodLoops.passes(source, config.relative(path), loops)
    Rewriter.rewrite(source, parsed[:decisions], reaches, passes)
  end

  # compiled, after noting each of its methods' loops and repeats,
  # [{ entry => loops }, { entry => repeats }], as MethodLoops
  # gives them, on the recorder's trace, and tracing each call of
  # them, and only of them, on the trace of whichever start is
  # current as it runs. Code with no method has no call to
  # trace, and TracePoint refuses to trace it.
  def self.traced(compiled, (loops, repeats))
    return compiled if loops.empty?

    loops.each do |entry, held|
      @recorder.trace.know(entry, held, repeats[entry])
    end
    hook = method(:on_call_event)
    TracePoint.new(:call, :return, &hook).enable(target: compiled)
    compiled
  end

  # Notes point, a TracePoint's :call or :return of a covered
  # method, on the current start's trace.
  def self.on_call_event(point)
    trace = @recorder.trace
    point.event == :call ? trace.call : trace.return
  end

  # Writes the JSON reports, then runs the chosen reporters, for
  # every covered file whether or not the run loaded it, from
  # the counts and decision paths this run recorded.
  def self.report(config)
    files = parsed_files(config)
    decisions = merged_decisions(files)
    result = Result.new(decisions, @recorder.counts,
                        @recorder.decision_paths)
    reached = @recorder.reached
    ways = @recorder.trace.ways
    Render.run(result.operands, files, config,
               **result.taken, reached:, ways:)
  end

  # { full path => {source:, decisions:} } for every covered file:
  # as parsed when it loaded, or parsed now for a file the run
  # never loaded.
  def self.parsed_files(config)
    config.files.to_h do |path|
      [path, @parsed.fetch(path) { Manifest.parse(path, config) }]
    end
  end

  # The decisions of every covered file, in one manifest.
  def self.merged_decisions(files)
    files.values.map do |parsed|
      parsed[:decisions]
    end.reduce({}, :merge)
  end
end
