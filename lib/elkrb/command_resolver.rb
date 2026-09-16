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
    #
    # On Windows, CreateProcess (what `system`/backtick ultimately calls) does
    # not require an exact filename match: given "dot" it also tries "dot"
    # suffixed with each extension in PATHEXT, in order, both for a bare name
    # walked along PATH and for a name given with a separator. POSIX exec has
    # no such behaviour, so `executable_candidates` is a no-op there.
    def runnable?(path)
      if separator_form?(path)
        executable_candidates(path).any? do |candidate|
          executable_file?(candidate)
        end
      else
        path_directories.any? { |dir| resolves_in_directory?(dir, path) }
      end
    end

    def separator_form?(path)
      return true if path.include?(File::SEPARATOR)

      windows? && File::ALT_SEPARATOR && path.include?(File::ALT_SEPARATOR)
    end

    def resolves_in_directory?(dir, path)
      executable_candidates(path).any? do |candidate|
        executable_file?(File.join(dir, candidate))
      end
    end

    # `File.executable?` alone is true for a DIRECTORY, because directories
    # are searchable, and exec is not. `File.file?` alone is true for a data
    # file. Both conjuncts are load-bearing.
    def executable_file?(path)
      File.file?(path) && File.executable?(path)
    end

    # A path that already carries a PATHEXT-listed extension (e.g. "dot.exe")
    # is used as written -- only an EXTENSION-LESS name gets the PATHEXT
    # fan-out, matching what CreateProcess actually does.
    def executable_candidates(path)
      return [path] unless windows?
      return [path] if pathext.include?(File.extname(path).upcase)

      pathext_candidates(path)
    end

    # The Windows filesystem is case-insensitive, so CreateProcess matches
    # "dot.exe" whether PATHEXT names it ".EXE" or ".exe". Trying both cases
    # here matches that on a case-SENSITIVE filesystem too (Linux/macOS CI
    # running this logic under a Windows stub), rather than depending on the
    # host filesystem's case sensitivity to agree.
    def pathext_candidates(path)
      pathext.flat_map do |extension|
        ["#{path}#{extension}", "#{path}#{extension.downcase}"]
      end.uniq
    end

    # PATHEXT is always ";"-delimited on Windows, independent of
    # `File::PATH_SEPARATOR` -- which on a non-Windows host running under a
    # stubbed `windows?` (as the specs do, to test this logic on any CI
    # platform) is ":" and would silently produce one useless candidate.
    def pathext
      ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
    end

    def windows?
      Gem.win_platform?
    end

    # Keep the `.b` and `split(..., -1)`: a raw (non-UTF-8) PATH byte must not
    # raise, and a trailing/empty field must not be dropped -- both silently
    # break resolution for a later, valid PATH entry otherwise. This is a
    # documented CONTAINMENT, not full parity with exec: an unset PATH here
    # is treated as empty, while exec also searches libruby's compiled-in
    # default list (see gate record for the measured value) -- so this can
    # under-report but never over-report a directory exec would search.
    def path_directories
      fields = ENV.fetch("PATH", "").b.split(File::PATH_SEPARATOR, -1)
      fields = [""] if fields.empty?
      fields.map { |field| field.empty? ? "." : expand_tilde(field) }
    end

    # Expand only a bare `~` or `~/...` PATH entry against `$HOME`, matching
    # what the shell does before `render`'s `system(cmd)` ever sees PATH.
    # Leave `~user` (a third party's home directory) un-expanded rather than
    # querying the OS user database -- it still cannot false-positive-match
    # via `executable_file?`, only under-report, same as `path_directories`.
    def expand_tilde(field)
      return field unless field.start_with?("~")

      tilde_expansion(field) || field
    end

    # Split from `expand_tilde` so each holds one job: this one turns a
    # confirmed `~` PATH entry into its expansion or nothing, and never
    # touches a field that is not one.
    def tilde_expansion(field)
      rest = tilde_rest(field)
      return unless rest

      home = home_directory
      return if home.to_s.empty?

      "#{home.b}#{rest}"
    end

    # `Dir.home` (not `ENV["HOME"]` directly) so this agrees with what the
    # shell itself consults for `~` expansion; it raises when no home
    # directory can be determined at all, rather than returning nil, so
    # that is the one case caught here.
    def home_directory
      Dir.home
    rescue ArgumentError
      nil
    end

    # `nil` means "not a `~` or `~/...` PATH entry" -- distinct from `""`,
    # which is the valid rest of a bare `~`. `field[1..]` is never nil here:
    # `field` always has at least one byte (the leading `~`), so index 1 is
    # at worst equal to its length, which slices to `""` rather than failing.
    def tilde_rest(field)
      rest = field[1..]
      rest if rest.empty? || rest.start_with?(File::SEPARATOR)
    end
  end
end

# Internal. Kept off the public surface deliberately; `private_constant` sits
# out here because inside the namespace it makes `Elkrb` a non-namespacing
# module, which reek then requires a descriptive comment for.
Elkrb.private_constant :CommandResolver
