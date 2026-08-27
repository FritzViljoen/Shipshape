# frozen_string_literal: true

require "shipshape/typed_arguments"

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
    end

    def for_path(path)
      return nil if path.nil?

      relative = relative_to_base(typed(path, String))
      return nil if relative.nil?

      settings.kinds.each do |kind, globs|
        return kind if globs.any? { |glob| File.fnmatch?(glob, relative, File::FNM_PATHNAME) }
      end
      nil
    end

    def for_constant(name)
      return nil if name.nil?

      typed(name, String)
      constant_cache.fetch(name) { constant_cache[name] = resolve_constant(name) }
    end

    private

    attr_reader :settings, :base_dir, :constant_cache

    def resolve_constant(name)
      relative = "#{underscore(name)}.rb"

      settings.kinds.each do |kind, globs|
        globs.each do |glob|
          return kind if File.file?(File.join(base_dir, root_of(glob), relative))
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

    # "app/commands/**/*.rb" -> "app/commands". Settings has already refused a glob whose
    # wildcards are not all at the tail, so this cannot silently truncate a real segment.
    def root_of(glob)
      glob.split("/").take_while { |segment| !segment.include?("*") }.join("/")
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
