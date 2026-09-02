# frozen_string_literal: true

require "shipshape/source_text"
require "shipshape/typed_arguments"

module Shipshape
  # Resolves a class's kind. The superclass decides it; the path only decides whether a file is
  # governed at all, which is what lets two kinds share one glob. The application is never
  # loaded, so the filesystem is the only thing that can answer, and nil means "not classified"
  # rather than "allowed" — callers skip on nil and count the skips.
  class Kinds
    include TypedArguments

    def initialize(settings:, base_dir:)
      @settings = typed(settings, Settings)
      @base_dir = typed(base_dir, String)
      @constant_cache = {}
      @root_cache = {}
      @superclass_cache = {}
    end

    def for_path(path)
      return nil if path.nil?

      relative = relative_to_base(typed(path, String))
      return nil if relative.nil?

      candidates = kinds_matching(relative)
      return nil if candidates.empty?

      by_base_class(path, candidates) || candidates.first
    end

    # A declared base class is its kind whatever file it lives in: a gem's constant resolves to
    # no file, so `ActiveRecord::Base.connection.execute` in a shape reached the database unseen.
    def for_constant(name)
      return nil if name.nil?

      typed(name, String)
      settings.kind_of_base_class(name) || (file_for_constant(name) && constant_cache[name].first)
    end

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

    public

    def superclass_of(path)
      superclass_in(path)
    end

    private

    def by_base_class(path, candidates)
      kind = settings.kind_of_base_class(superclass_in(path))
      return nil if kind.nil?

      candidates.include?(kind) ? kind : nil
    end

    SUPERCLASS = /^\s*class\s+[\w:]+\s*<\s*([\w:]+)/.freeze

    def superclass_in(path)
      superclass_cache.fetch(path) do
        superclass_cache[path] = File.file?(path) ? SourceText.read(path)[SUPERCLASS, 1] : nil
      end
    end

    def resolve_constant(name)
      relative = "#{underscore(name)}.rb"

      settings.kinds.each_value do |globs|
        globs.each do |glob|
          found = wildcard?(glob) ? under_roots(glob, relative) : named_file(glob, relative)
          return [for_path(found), found] if found
        end
      end
      nil
    end

    # A `**` root matches at any depth, so an unnamespaced file falls back to a recursive search.
    def under_roots(glob, relative)
      recursive = glob.include?("**")

      roots_of(glob).each do |root|
        exact = File.join(root, relative)
        return exact if File.file?(exact)

        found = recursive && Dir.glob(File.join(root, "**", relative)).find { |path| File.file?(path) }
        return found if found
      end

      nil
    end

    # A glob naming one file is not a root: resolving constants against its directory classified
    # every neighbour the same, and reported a controller reaching into a record as clean.
    def named_file(glob, relative)
      absolute = File.join(base_dir, glob)
      return nil unless absolute.end_with?("/#{relative}") && File.file?(absolute)

      absolute
    end

    def wildcard?(glob)
      glob.include?("*")
    end

    def relative_to_base(path)
      absolute = File.expand_path(path)
      prefix = "#{File.expand_path(base_dir)}/"
      return nil unless absolute.start_with?(prefix)

      absolute[prefix.length..-1]
    end

    # Trailing wildcards drop and the rest expands on disk — the FIRST wildcard alone resolved every pack against `packs`.
    def roots_of(glob)
      root_cache[glob] ||= begin
        segments = glob.split("/")
        segments.pop while segments.last && segments.last.include?("*")
        pattern = File.join(base_dir, segments.join("/"))

        pattern.include?("*") ? Dir.glob(pattern).select { |path| File.directory?(path) } : [pattern]
      end
    end

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
