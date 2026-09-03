# frozen_string_literal: true

require "json"
require "securerandom"
require "yaml"
require "fileutils"

module Elkrb
  module Commands
    # Command for creating diagrams from ELK graph files
    # Supports multiple input formats (JSON, YAML, ELKT) and output formats (DOT, PNG, SVG, PDF)
    class DiagramCommand
      def initialize(file, options)
        @file = file
        @options = options
      end

      def run
        # Load graph
        graph = load_graph(@file)

        # Apply layout
        layout_options = build_layout_options
        result = Elkrb::Layout::LayoutEngine.layout(graph, layout_options)

        # Determine output format
        output_format = detect_format(@options[:output])

        # Export to format
        content = export_to_format(result, output_format)

        # An image format NEVER has DOT written under its own name. The DOT
        # went to `out.svg` first and was read back for rendering, so any
        # failure between those two points left the caller an `out.svg` that
        # began `digraph G{`. Cleanup could not be relied on to undo it
        # either: `FileUtils.rm_f` swallows an unlink failure, so in a
        # non-writable directory the misleading file simply stayed.
        #
        # Staging under a separate name means the image path is only ever
        # written by a render that succeeded.
        if image_format?(output_format)
          render_to_image(content, @options[:output], output_format)
        else
          write_output(content, @options[:output])
        end

        # Preview if requested
        preview(@options[:output]) if @options[:preview]

        puts "✓ Diagram created: #{@options[:output]}"
      end

      private

      def load_graph(file)
        raise ArgumentError, "File not found: #{file}" unless File.exist?(file)

        require_relative "../format_sniffer"
        Elkrb::FormatSniffer.read(File.read(file), File.extname(file).downcase)
      end

      def build_layout_options
        opts = {}

        opts[:algorithm] = @options[:algorithm] if @options[:algorithm]
        opts[:direction] = @options[:direction] if @options[:direction]
        opts[:spacing_node_node] = @options[:spacing] if @options[:spacing]
        opts[:edge_routing] = @options[:edge_routing] if @options[:edge_routing]

        opts
      end

      def detect_format(filename)
        ext = File.extname(filename).downcase

        case ext
        when ".json" then :json
        when ".yml", ".yaml" then :yaml
        when ".dot", ".gv" then :dot
        when ".elkt" then :elkt
        when ".png" then :png
        when ".svg" then :svg
        when ".pdf" then :pdf
        when ".ps" then :ps
        when ".eps" then :eps
        else
          # Use explicit format option if provided
          if @options[:format]
            @options[:format].to_sym
          else
            :dot # Default to DOT
          end
        end
      end

      def export_to_format(result, format)
        case format
        when :json
          # Use Lutaml-model's to_json for proper serialization
          result.to_json
        when :yaml
          # Use Lutaml-model's to_yaml for proper serialization
          result.to_yaml
        when :dot, :png, :svg, :pdf, :ps, :eps
          require_relative "../serializers/dot_serializer"
          Elkrb::Serializers::DotSerializer.new.serialize(result)
        when :elkt
          require_relative "../serializers/elkt_serializer"
          Elkrb::Serializers::ElktSerializer.new.serialize(result)
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      def write_output(content, filename)
        dir = File.dirname(filename)
        FileUtils.mkdir_p(dir)

        File.write(filename, content)
      end

      IMAGE_FORMATS = %i[png svg pdf ps eps].freeze
      private_constant :IMAGE_FORMATS

      def image_format?(format)
        IMAGE_FORMATS.include?(format)
      end

      # Renders to a SCRATCH path and moves it into place only once the
      # render has succeeded. Nothing else makes the guarantee hold.
      #
      # Rendering straight to `output_file` and cleaning up afterwards does
      # not work, and both attempts at it failed differently. Deleting
      # unconditionally destroyed a file the caller already had there.
      # Deleting only when we had created it left a TRUNCATED image behind --
      # measured, a 1024-byte file beginning `<?xml` from a render that died
      # partway, sitting under the caller's own filename. `File.rename` is
      # atomic within a filesystem, so the image path either holds the
      # previous content or a complete render, never a fragment.

      def render_to_image(dot_content, output_file, format)
        # A scratch DIRECTORY, created exclusively, holding both scratch
        # files under plain names.
        #
        # Scratch names must be unguessable: with a fixed name like
        # `out.svg.tmp.svg`, a symlink sitting there and pointing back at
        # `out.svg` sent a failed render's partial output onto the caller's
        # file, and two concurrent renders of the same target collided the
        # same way.
        #
        # A directory rather than pre-created FILES, because reserving each
        # file by creating it first broke four other things: it defeated a
        # renderer that exits 0 without writing (the untouched empty file got
        # renamed over the caller's content), it left the file mode at the
        # umask so a later write could not open it, and it added enough to
        # the basename to hit ENAMETOOLONG on a long but legal filename.
        # `Dir.mkdir` is atomic and refuses an existing path, so it reserves
        # the name without any of that.
        #
        # The directory lives in the DESTINATION directory, which keeps
        # `File.rename` on one filesystem and therefore atomic.
        FileUtils.mkdir_p(File.dirname(output_file))
        scratch, identity, token = scratch_dir(output_file)
        dot_file = File.join(scratch, "graph-#{token}.dot")
        image_file = File.join(scratch, "image-#{token}.#{format}")

        begin
          write_output(dot_content, dot_file)

          require_relative "../graphviz_wrapper"
          graphviz = Elkrb::GraphvizWrapper.new

          graphviz.render(dot_file, image_file, format, engine: "dot", dpi: 96)

          # A renderer can exit 0 and write nothing. Renaming that over the
          # requested name would destroy the caller's file and leave an
          # invalid image wearing its name -- measured with a stub renderer
          # that simply succeeds.
          unless File.file?(image_file) && File.size(image_file).positive?
            raise Elkrb::Error,
                  "#{graphviz_name} reported success but produced no image"
          end

          File.rename(image_file, output_file)
        ensure
          remove_scratch(scratch, identity, [dot_file, image_file])
        end
      end

      def graphviz_name
        "graphviz"
      end

      # A directory in the destination that did not exist a moment ago and
      # that this process created. `Dir.mkdir` raises EEXIST rather than
      # opening what is already there, which is what makes that true.
      #
      # Returns the path AND the directory's identity -- device and inode --
      # because a path is not a durable handle. Cleanup compares that identity
      # before removing anything, so if the entry is swapped for a different
      # real directory in between, that directory is left alone.
      def scratch_dir(output_file)
        dir = File.dirname(output_file)

        loop do
          # A SECOND token, never used in a path anybody else can see. The
          # directory name is visible in the parent listing; the names of the
          # files inside it are not, because the directory is 0700 and ours.
          # Cleanup unlinks only those two names, so a directory swapped in
          # at this path would have to already contain a name derived from a
          # token it cannot observe.
          token = SecureRandom.hex(6)
          candidate = File.join(dir, ".elkrb-#{SecureRandom.hex(6)}")
          begin
            Dir.mkdir(candidate)
          rescue Errno::EEXIST
            next
          end

          return claim_scratch(candidate, token)
        end
      end

      # Everything from here has already created the directory, and the
      # caller's `ensure` has not begun yet -- so this is the only place that
      # can clean it up. A chmod that raised used to leak it.
      def claim_scratch(candidate, token)
        identity = directory_identity(candidate)
        # `Dir.mkdir`'s mode is masked by the umask, so under `umask 0222`
        # the directory arrives read-only and nothing can be written inside
        # it. Set the mode after creating, not as an argument.
        FileUtils.chmod(0o700, candidate)
        [candidate, identity, token]
      rescue StandardError
        discard_claim(candidate, identity)
        raise
      end

      # Cleanup for a directory created moments ago, where the failure may be
      # the identity capture ITSELF -- so `identity` can be nil here.
      #
      # With an identity, compare it. Without one, remove NON-recursively: the
      # directory we made is still empty, and `Dir.rmdir` refuses one that is
      # not, so anything a replacement contains survives. A recursive delete
      # by path here would take that replacement and everything in it --
      # measured, it did.
      def discard_claim(candidate, identity)
        return remove_scratch(candidate, identity, []) if identity

        begin
          Dir.rmdir(candidate)
        rescue SystemCallError
          nil
        end
      end

      def directory_identity(path)
        stat = File.lstat(path)
        [stat.dev, stat.ino]
      end

      # Removes the directory ONLY if the path still names the one whose
      # identity was captured, and removes nothing else at all.
      #
      # `entries` are the exact two paths `render_to_image` built, both
      # carrying a token that never appears anywhere another process can
      # read: the directory is 0700 and ours, so the names inside it are not
      # observable from outside. A directory substituted at this path would
      # have to already contain a file named for a token it cannot see, and
      # `Dir.rmdir` refuses anything not empty -- so a substitute keeps both
      # its contents and itself.
      #
      # There is no recursive delete here on purpose. Comparing the identity
      # and then calling `FileUtils.remove_entry` were two separate
      # operations, and a directory substituted between them was removed with
      # everything in it. The identity check narrowed that window; only
      # removing the recursion closes it.
      def remove_scratch(path, identity, entries = [])
        return if identity.nil?
        return unless File.directory?(path)
        return unless directory_identity(path) == identity

        entries.each { |entry| unlink_quietly(entry) }
        remove_empty_directory(path, identity)
      end

      def unlink_quietly(path)
        File.unlink(path)
      rescue SystemCallError
        nil
      end

      # Scoped so a missing DESCENDANT cannot be mistaken for a missing root:
      # a method-wide ENOENT rescue swallowed that and left the directory.
      #
      # The identity is compared AGAIN here, after the unlinks. The first
      # comparison was several syscalls ago, and this is the call that
      # removes a directory.
      def remove_empty_directory(path, identity)
        return unless directory_identity(path) == identity

        Dir.rmdir(path)
      rescue SystemCallError
        nil
      end

      def preview(file)
        case RbConfig::CONFIG["host_os"]
        when /darwin/
          system("open", file)
        when /linux/
          system("xdg-open", file)
        when /mswin|mingw|cygwin/
          system("start", file)
        else
          warn "Preview not supported on this platform"
        end
      end
    end
  end
end
