# frozen_string_literal: true

module Shipshape
  # Resolves a class's kind, which is what the call matrix is stated in terms of.
  #
  # Two directions, and they are deliberately different:
  #
  # - **A file** is resolved by matching its path against the kind's globs. The file is in
  #   front of us, so this is exact.
  # - **A constant** is resolved by turning its name into the relative path the loader
  #   would expect and asking whether that file exists under any kind's root. We do not
  #   load the application, so the filesystem is the only thing that can answer.
  #
  # Either may answer nil, and nil means "not classified" rather than "allowed". Callers
  # skip on nil and count the skips — a silently unclassified tree is the coverage-shaped
  # hole `a-guard-states-its-limit` warns about.
  class Kinds
    def initialize(globs_by_kind:, base_dir:)
      @globs_by_kind = globs_by_kind
      @base_dir = base_dir
      @constant_cache = {}
    end

    def for_path(path)
      return nil if path.nil?

      relative = relative_to_base(path)
      return nil if relative.nil?

      globs_by_kind.each do |kind, globs|
        return kind if globs.any? { |glob| File.fnmatch?(glob, relative, File::FNM_PATHNAME) }
      end
      nil
    end

    def for_constant(name)
      return nil if name.nil?

      constant_cache.fetch(name) { constant_cache[name] = resolve_constant(name) }
    end

    private

    attr_reader :globs_by_kind, :base_dir, :constant_cache

    def resolve_constant(name)
      relative = "#{underscore(name)}.rb"

      globs_by_kind.each do |kind, globs|
        globs.each do |glob|
          root = root_of(glob)
          return kind if File.file?(File.join(base_dir, root, relative))
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

    # "app/operations/**/*.rb" -> "app/operations"
    def root_of(glob)
      glob.split("/").take_while { |segment| !segment.include?("*") }.join("/")
    end

    # Deliberately not ActiveSupport's: the gem takes no Rails dependency, and the
    # acronym table is the part that would drift. A constant an application spells with
    # an acronym resolves to no file and comes back nil, which is the honest answer.
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
