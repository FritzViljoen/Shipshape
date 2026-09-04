# frozen_string_literal: true

require "json"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"
require "shipshape/unrecognized_cops"

module Shipshape
  # How many offences each cop found, counting only Shipshape's own. A subprocess rather than
  # in-process, because RuboCop resolves configuration relative to where it starts and the two
  # runs happen in two directories.
  class Offences
    include TypedArguments

    DEPARTMENT = "Shipshape"

    def initialize(directory:, config: nil, tolerate_unknown_cops: false)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
      @tolerate_unknown_cops = tolerate_unknown_cops
      @skipped_cops = []
    end

    def call
      Hash.new(0).merge(by_cop.transform_values(&:length))
    end

    def paths_for(cop_name) # what Check reads to measure what an offence count alone cannot
      by_cop.fetch(cop_name, []).map { |offence| offence.fetch(:path) }.uniq
    end

    # Only meaningful after `call` (or `paths_for`) has run once - see `#json`.
    attr_reader :skipped_cops

    private

    attr_reader :directory, :config, :tolerate_unknown_cops

    def by_cop
      @by_cop ||= JSON.parse(json).fetch("files", []).each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, grouped|
        path = file.fetch("path").sub(%r{\A\./}, "")

        file.fetch("offenses", []).each do |offence|
          name = offence.fetch("cop_name")
          grouped[name] << { path: path } if name.start_with?("#{DEPARTMENT}/")
        end
      end
    end

    # Exit 1 is normal, so only the parse is checked: a crash is not "none found".
    def json
      out, err, = Open3.capture3(*command, chdir: directory)
      @skipped_cops = UnrecognizedCops.named_in(err) if tolerate_unknown_cops
      return out if out.start_with?("{")

      raise Error, "shipshape: rubocop produced no report in #{directory}: #{err.strip}"
    end

    def command
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--format", "json", "--no-color"]
      arguments << "--ignore-unrecognized-cops" if tolerate_unknown_cops
      arguments += ["--config", config] if config

      arguments
    end

    def rubocop
      @rubocop ||= Gem.bin_path("rubocop", "rubocop")
    rescue Gem::Exception
      raise Error, "shipshape: rubocop is not installed in this environment."
    end
  end
end
