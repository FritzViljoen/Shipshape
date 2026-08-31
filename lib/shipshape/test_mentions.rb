# frozen_string_literal: true

require "shipshape/source_text"

module Shipshape
  # Whether the suite names a method anywhere.
  class TestMentions
    include TypedArguments

    # One level deep too: solidus has no top-level `spec/`, and every edge read as untested.
    DIRECTORIES = %w[test spec */test */spec].freeze

    TOO_COMMON = %w[
      initialize call to_s to_h to_a inspect each map new name id type value
      first last count length size empty? present? blank? nil? key? include?
    ].freeze

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

    # Ruby's own vocabulary is no evidence either way, so it is left out of the count.
    def too_common?(method)
      TOO_COMMON.include?(method.to_s.sub(/[?!=]\z/, ""))
    end

    def any?
      !source.empty?
    end

    private

    attr_reader :root, :directories

    def source
      @source ||= directories.flat_map { |directory|
        Dir.glob(File.join(root, directory, "**", "*.rb"))
      }.map { |file| SourceText.read(file) }.join("\n")
    end
  end
end
