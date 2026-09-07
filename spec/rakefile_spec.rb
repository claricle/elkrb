# frozen_string_literal: true

require "ripper"

# The Rakefile is loadable by any Ruby process -- `load "Rakefile"`, or
# Rake::Application#load_rakefile from an embedding tool -- so a bare `abort`
# in a task body terminates its CALLER with SystemExit instead of failing the
# task. Only a script entry point may decide a process exit status.
RSpec.describe "Rakefile" do
  let(:path) { File.expand_path("../Rakefile", __dir__) }

  # Structural, and deliberately so: the property is about the whole file, not
  # about the three task bodies that happen to have a failure path today. An
  # example per task would leave every task added later uncovered. Ripper drops
  # comments and string bodies, so only a real call site is reported.
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
    walk.call(Ripper.sexp(File.read(path)))

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
