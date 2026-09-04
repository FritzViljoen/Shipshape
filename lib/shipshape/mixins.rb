# frozen_string_literal: true

require "set"
require "shipshape/source_text"
require "shipshape/typed_arguments"

module Shipshape
  # Which module names an operation mixes in. The question runs backwards from every other one
  # here: a module cannot answer for itself, because `concerns/paying.rb` is legitimate in a
  # shape and not in a deed. Names, not files — `Kinds` resolves only within kind globs, so
  # the module the rule most exists for came back nil. Read rather than parsed, so a computed
  class Mixins
    include TypedArguments

    INCLUDE = /^\s*(?:include|prepend)\s+((?:::)?[A-Z][\w:]*)/.freeze

    def initialize(settings:, base_dir:, operation_kinds:)
      @settings = typed(settings, Settings)
      @base_dir = typed(base_dir, String)
      @operation_kinds = typed(operation_kinds, Array)
      @written_names = nil
    end

    def mixed_into_an_operation?(declared_name)
      return false if declared_name.nil?

      typed(declared_name, String)
      written_names.any? { |written| names_the_same_module?(written, declared_name) }
    end

    private

    attr_reader :settings, :base_dir, :operation_kinds

    def names_the_same_module?(written, declared)
      written == declared || declared.end_with?("::#{written}")
    end

    def written_names
      @written_names ||= operation_files.flat_map { |file| included_in(file) }.to_set
    end

    def included_in(file)
      SourceText.read(file).scan(INCLUDE).flatten.map { |name| name.sub(/\A::/, "") }
    rescue SystemCallError
      []
    end

    def operation_files
      settings.kinds
              .select { |kind, _globs| operation_kinds.include?(kind) }
              .values.flatten
              .flat_map { |glob| Dir.glob(File.join(base_dir, glob)) }
              .uniq
              .select { |path| File.file?(path) }
    end
  end
end
