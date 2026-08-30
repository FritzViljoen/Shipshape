# frozen_string_literal: true

require "shipshape/source_text"

module Shipshape
  # Whether the suite names a method anywhere.
  #
  # **A name match, not a call graph.** A method named in a comment counts, and one called
  # through `send` does not — it answers "would anything notice if this changed", which is the
  # question, and a precise answer would mean running the suite.
  #
  # Extracted so `Queue` and `Edges` ask it the same way. Two copies of a heuristic is two
  # heuristics, and they drift.
  class TestMentions
    include TypedArguments

    # **One level deep as well as at the root.** A monorepo keeps its suites per engine —
    # solidus has `core/spec`, `api/spec`, `admin/spec` and no top-level `spec/` at all — and
    # looking only at the root found nothing there and reported every edge untested. A false
    # 100% sends somebody writing tests that already exist.
    DIRECTORIES = %w[test spec */test */spec].freeze

    # Ruby's own vocabulary, and the words every test file contains anyway. Matching these
    # would mark everything covered.
    TOO_COMMON = %w[
      initialize call to_s to_h to_a inspect each map new name id type value
      first last count length size empty? present? blank? nil? key? include?
    ].freeze

    # Under four characters matches too much of anything.
    SHORTEST = 4

    def initialize(root:, directories: DIRECTORIES)
      @root = typed(root, String)
      @directories = typed_array(directories, String)
    end

    def names?(word)
      bare = word.to_s.sub(/[?!=]\z/, "")
      return false if bare.length < SHORTEST

      source.include?(bare)
    end

    # **Ruby's own vocabulary is not evidence either way.** `call`, `name`, `each` appear in
    # every suite whether or not this class is tested, so a caller counting method coverage
    # leaves them out of the count entirely rather than calling them uncovered — the second
    # would overstate the work as badly as matching them would understate it.
    def too_common?(method)
      TOO_COMMON.include?(method.to_s.sub(/[?!=]\z/, ""))
    end

    def any?
      !source.empty?
    end

    private

    attr_reader :root, :directories

    # Read once. A grep per method over a large suite is minutes, and callers ask per file.
    def source
      @source ||= directories.flat_map { |directory|
        Dir.glob(File.join(root, directory, "**", "*.rb"))
      }.map { |file| SourceText.read(file) }.join("\n")
    end
  end
end
