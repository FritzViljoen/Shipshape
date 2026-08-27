# frozen_string_literal: true

require "shipshape/typed_arguments"

module Shipshape
  # Resolves a class's kind, which is what the call matrix is stated in terms of.
  #
  # **The superclass decides the kind. The path only decides whether a file is governed at
  # all** — which is what lets two kinds share one glob, as the legacy pair do: `*_legacy.rb`
  # says "this is a door", and the base class says which of the two. Where a governed file
  # names no declared base class, its path decides instead.
  #
  # A constant is resolved by turning its name into the relative path the loader would
  # expect and asking whether that file exists under any kind's root; the file it lands on
  # is then classified exactly as any other file is. We do not load the application, so the
  # filesystem is the only thing that can answer.
  #
  # Either may answer nil, and nil means "not classified" rather than "allowed". Callers
  # skip on nil and count the skips — a silently unclassified tree is the coverage-shaped
  # hole `a-guard-states-its-limit` warns about.
  #
  # Its arguments were asserted at the seam by Settings before they got here, and they are
  # asserted again on arrival because this class is public and a second caller may not have
  # come through the seam. Inside, nothing re-checks.
  class Kinds
    include TypedArguments

    def initialize(settings:, base_dir:)
      @settings = typed(settings, Settings)
      @base_dir = typed(base_dir, String)
      @constant_cache = {}
      @root_cache = {}
      @superclass_cache = {}
    end

    # The superclass decides the kind; the path only decides whether the file is governed
    # at all. That is what lets two kinds share one glob — the legacy pair do, because
    # `*_legacy.rb` says "this is a door" and the base class says which of the two it is.
    #
    # Path is the fallback, for a governed file whose superclass names nothing declared.
    def for_path(path)
      return nil if path.nil?

      relative = relative_to_base(typed(path, String))
      return nil if relative.nil?

      candidates = kinds_matching(relative)
      return nil if candidates.empty?

      by_base_class(path, candidates) || candidates.first
    end

    def for_constant(name)
      return nil if name.nil?

      typed(name, String)
      file_for_constant(name) && constant_cache[name].first
    end

    # The file a constant resolves to, so a caller can tell a sister call from a class
    # referring to itself. `Result.success(...)` inside `Result` is not two entities
    # talking; it is one entity, and the call graph has nothing to say about it.
    def file_for_constant(name)
      return nil if name.nil?

      typed(name, String)
      resolved = constant_cache.fetch(name) { constant_cache[name] = resolve_constant(name) }
      resolved && resolved.last
    end

    private

    attr_reader :settings, :base_dir, :constant_cache, :root_cache, :superclass_cache

    def kinds_matching(relative)
      settings.kinds.select do |_kind, globs|
        globs.any? { |glob| File.fnmatch?(glob, relative, File::FNM_PATHNAME) }
      end.keys
    end

    def by_base_class(path, candidates)
      kind = settings.kind_of_base_class(superclass_in(path))
      return nil if kind.nil?

      candidates.include?(kind) ? kind : nil
    end

    # Read rather than parsed, and matched on the first `class X < Y` in the file.
    #
    # Parsing every referenced file with the full parser would be correct and slow; this is
    # a regular expression over source, so a superclass written as an expression, assigned
    # through a constant, or produced by a class-generating call is invisible and the file
    # falls back to its path. `one-level-of-inheritance` is what keeps that rare.
    SUPERCLASS = /^\s*class\s+[\w:]+\s*<\s*([\w:]+)/.freeze

    def superclass_in(path)
      superclass_cache.fetch(path) do
        superclass_cache[path] = File.file?(path) ? File.read(path)[SUPERCLASS, 1] : nil
      end
    end

    # Answers [kind, file] or nil. The file is kept for two reasons: a class referring to
    # itself is not a call between two of a kind, and the kind itself comes from reading
    # that file's superclass — so the constant is resolved to a path first and classified
    # exactly as any other file would be.
    def resolve_constant(name)
      relative = "#{underscore(name)}.rb"

      settings.kinds.each_value do |globs|
        globs.each do |glob|
          roots_of(glob).each do |root|
            candidate = File.join(root, relative)
            return [for_path(candidate), candidate] if File.file?(candidate)
          end
        end
      end
      nil
    end

    def relative_to_base(path)
      absolute = File.expand_path(path)
      prefix = "#{File.expand_path(base_dir)}/"
      return nil unless absolute.start_with?(prefix)

      absolute[prefix.length..-1]
    end

    # The autoload roots a glob covers — what a constant name is resolved against.
    #
    # Trailing wildcard segments are dropped, and what remains is expanded on disk, so a
    # Packwerk layout works: `packs/*/app/commands/**/*.rb` drops `**` and `*.rb`, leaving
    # `packs/*/app/commands`, which expands to one root per pack. An earlier version took
    # everything before the FIRST wildcard, which resolved every packs constant against
    # `packs` and matched nothing at all — silently, which is the worse half.
    #
    # Expansion reads the disk, so it is memoised per glob. A pack added mid-run is not
    # seen; nothing adds one mid-run.
    def roots_of(glob)
      root_cache[glob] ||= begin
        segments = glob.split("/")
        segments.pop while segments.last && segments.last.include?("*")
        pattern = File.join(base_dir, segments.join("/"))

        pattern.include?("*") ? Dir.glob(pattern).select { |path| File.directory?(path) } : [pattern]
      end
    end

    # Deliberately not ActiveSupport's: the gem takes no Rails dependency, and the acronym
    # table is the part that would drift. A constant an application spells with an acronym
    # resolves to no file and comes back nil, which is the honest answer.
    def underscore(name)
      name.split("::").map { |segment| underscore_segment(segment) }.join("/")
    end

    def underscore_segment(segment)
      segment
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
    end
  end
end
