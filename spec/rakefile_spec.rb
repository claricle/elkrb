# frozen_string_literal: true

require "rbconfig"
require "ripper"

# The Rakefile is loadable by any Ruby process -- `load "Rakefile"`, or
# Rake::Application#load_rakefile from an embedding tool -- so a bare `abort`
# in a task body terminates its CALLER with SystemExit instead of failing the
# task. Only a script entry point may decide a process exit status.
RSpec.describe "Rakefile" do
  let(:path) { File.expand_path("../Rakefile", __dir__) }

  # Structural, and deliberately so: the property is about the whole file, not
  # about the three task bodies that happen to have a failure path today. An
  # example per task would leave every task added later uncovered.
  #
  # The scan OVER-reports, and that is the safe direction for a guard: a false
  # positive is a failing build someone reads, a false negative ships an
  # `abort`. Measured on ruby 3.4.8, what a bare `:@ident` match does and does
  # not see:
  #
  #   abort "boom"           -> ["abort"]   the real call site, caught
  #   obj.exit               -> ["exit"]    a call on a receiver
  #   def exit; end          -> ["exit"]    a method DEFINITION, not a call
  #   h[:exit] = 1           -> ["exit"]    a symbol key, not a call
  #   exit_code = 1          -> []          not matched, the token differs
  #   # abort in a comment   -> []          Ripper drops comments
  #   puts "abort"           -> []          Ripper drops string bodies
  #
  # So the last three rows are what this buys over a grep; the middle two are
  # accepted noise. Narrowing to call-node shapes would risk missing a real
  # terminator, which is the failure this file exists to prevent.
  it "makes no process-terminating call" do
    terminators = []
    walk = lambda do |node|
      case node
      when Array
        if node[0] == :@ident && %w[abort exit exit!].include?(node[1])
          terminators << [node[1], node[2].first]
        end
        node.each { |child| walk.call(child) }
      end
    end
    sexp = Ripper.sexp(File.read(path))
    # Ripper.sexp returns nil -- not a raise -- when the source does not
    # parse. Walking nil yields no terminators, so without this the example
    # would report a syntactically BROKEN Rakefile as free of `abort`.
    # Verified: Ripper.sexp("task :x do\n  abort \"boom\"\n") -> nil.
    expect(sexp).not_to be_nil, "Rakefile did not parse; this example cannot " \
                                "judge it. Fix the syntax error first."
    walk.call(sexp)

    expect(terminators).to eq([])
  end

  # The positive control for the example above, and the property it stands in
  # for: an embedding process must SURVIVE a failing task. `corpus:dump` is the
  # one failure path that needs nothing but Rake itself. Out of process, so the
  # Rakefile's own constants cannot collide with an outer `rake` run.
  it "lets an embedding process survive a failing task" do
    probe = <<~PROBE
      require "rake"
      app = Rake::Application.new
      Rake.application = app
      app.init("rake", [])
      load #{path.inspect}
      begin
        app["corpus:dump"].invoke("")
        puts "NO-RAISE"
      rescue SystemExit
        puts "SYSTEMEXIT"
      rescue StandardError => e
        puts "STANDARDERROR"
      end
      puts "SURVIVED"
    PROBE

    out = IO.popen([RbConfig.ruby, "-e", probe], err: File::NULL, &:read)

    expect(out.split("\n").last(2)).to eq(%w[STANDARDERROR SURVIVED])
  end
end
