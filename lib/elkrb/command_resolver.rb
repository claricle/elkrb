# frozen_string_literal: true

module Elkrb
  # Resolves a command name to the file the OS would attempt to execute for
  # it, without running it. That is strictly weaker than "it will run": a
  # script whose interpreter is missing is a regular file, is executable, and
  # still fails to exec. What this establishes is WHICH file the name reaches.
  # Ruby execs a metacharacter-free command string itself and searches PATH
  # for it, so a name with a separator is used as written and a bare name is
  # looked up along PATH. Asking that question is a job of its own, separate
  # from running the command, and it carries no instance state -- the answer
  # depends on PATH, the filesystem and the working directory, none of which
  # this unit owns.
  module CommandResolver
    module_function

    # The first candidate that resolves, or nil.
    def resolve(candidates)
      candidates.find { |path| runnable?(path) }
    end

    # `File.executable?` on a bare name answers about the WORKING DIRECTORY
    # rather than about PATH, which is why it is not asked here.
    def runnable?(path)
      return executable_file?(path) if path.include?(File::SEPARATOR)

      path_directories.any? { |dir| executable_file?(File.join(dir, path)) }
    end

    # `File.executable?` alone is true for a DIRECTORY, because directories
    # are searchable, and exec is not. `File.file?` alone is true for a data
    # file. Both conjuncts are load-bearing.
    def executable_file?(path)
      File.file?(path) && File.executable?(path)
    end

    # Split as BYTES, because that is what the OS searches. A PATH entry
    # need not be valid UTF-8, and String#split raises ArgumentError on one
    # rather than skipping it -- so a single stray byte anywhere in PATH
    # would otherwise make resolution impossible while exec still finds a
    # real command in a later, valid entry.
    #
    # An empty PATH field means the working directory, and PATH="" is one
    # empty field. Ruby's split disagrees with that model twice, both
    # measured: "/usr/bin:".split(":") drops the trailing field, and
    # "".split(":", -1) yields no fields at all rather than one empty one.
    # An unset PATH is treated as an empty one, which is a CONTAINMENT and
    # not an equivalence. Both end in the working directory, but an unset
    # PATH also searches libruby's compiled-in default, measured on this
    # build as "/usr/local/bin:/usr/ucb:/usr/bin:/bin:." -- so the directories
    # searched here are a strict subset of the ones exec searches.
    #
    # That bounds one thing only: this never matches in a directory exec would
    # not look in. It does NOT promise exec runs the file matched here. The
    # working directory is LAST in that default list, so for an unset PATH an
    # installed command of the same bare name answers first.
    def path_directories
      fields = ENV.fetch("PATH", "").b.split(File::PATH_SEPARATOR, -1)
      fields = [""] if fields.empty?
      fields.map { |field| field.empty? ? "." : field }
    end
  end
end

# Internal. Kept off the public surface deliberately; `private_constant` sits
# out here because inside the namespace it makes `Elkrb` a non-namespacing
# module, which reek then requires a descriptive comment for.
Elkrb.private_constant :CommandResolver
