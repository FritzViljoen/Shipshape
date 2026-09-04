# frozen_string_literal: true

require "stringio"
require "rubocop"
require "shipshape/typed_arguments"
require "shipshape/unrecognized_cops"

module Shipshape
  # One tree's RuboCop config, read against this version's own cop registry. See the coupling law.
  class ConfigAt
    include TypedArguments

    Result = Struct.new(:config, :skipped_cops, keyword_init: true)

    def self.call(dir, config: nil, tolerate_unknown_cops: false)
      new(dir, config: config, tolerate_unknown_cops: tolerate_unknown_cops).call
    end

    def initialize(dir, config: nil, tolerate_unknown_cops: false)
      @dir = typed(dir, String)
      @config = typed(config, String, allow_nil: true)
      @tolerate_unknown_cops = tolerate_unknown_cops
    end

    def call
      return Result.new(config: store.for_dir(dir), skipped_cops: []) unless tolerate_unknown_cops

      loaded = nil
      warnings = capture_stderr { loaded = load_tolerantly }

      Result.new(config: loaded, skipped_cops: UnrecognizedCops.named_in(warnings))
    end

    private

    attr_reader :dir, :config, :tolerate_unknown_cops

    def load_tolerantly
      previous = RuboCop::ConfigLoader.ignore_unrecognized_cops
      RuboCop::ConfigLoader.ignore_unrecognized_cops = true
      store.for_dir(dir)
    ensure
      RuboCop::ConfigLoader.ignore_unrecognized_cops = previous
    end

    def store
      RuboCop::ConfigStore.new.tap { |s| s.options_config = config if config && File.file?(config) }
    end

    def capture_stderr
      original = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = original
    end
  end
end
