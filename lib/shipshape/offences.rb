# frozen_string_literal: true

require "json"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # How many offences each cop found, counting only Shipshape's own. A subprocess rather than
  # in-process, because RuboCop resolves configuration relative to where it starts and the two
  # runs happen in two directories.
  class Offences
    include TypedArguments

    DEPARTMENT = "Shipshape"

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    def call
      report = JSON.parse(json)

      report.fetch("files", []).each_with_object(Hash.new(0)) do |file, counts|
        file.fetch("offenses", []).each do |offence|
          name = offence.fetch("cop_name")
          counts[name] += 1 if name.start_with?("#{DEPARTMENT}/")
        end
      end
    end

    private

    attr_reader :directory, :config

    # Exit 1 is the normal case, so the status is not checked. What is checked is that the
    # output parses: a crash answers something that is not JSON, and that is not "none found".
    def json
      out, err, = Open3.capture3(*command, chdir: directory)
      return out if out.start_with?("{")

      raise Error, "shipshape: rubocop produced no report in #{directory}: #{err.strip}"
    end

    def command
      arguments = [RbConfig.ruby, rubocop, "--format", "json", "--no-color"]
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
