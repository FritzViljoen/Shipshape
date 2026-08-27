# frozen_string_literal: true

require "json"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Runs RuboCop in one directory and answers how many offences each cop found.
  #
  # **Only Shipshape's own cops are counted.** The ratchet governs this gem's rules; the
  # application's other cops are its own business, and gating a build on them without being
  # asked is how a tool gets removed.
  #
  # RuboCop is invoked as a subprocess rather than in-process, because the two runs happen in
  # two directories and RuboCop resolves configuration, `Include` and `Exclude` relative to
  # where it starts. Running both the same way is the only way the comparison means anything.
  class Offences
    include TypedArguments

    DEPARTMENT = "Shipshape"

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    # Answers { "Shipshape/CallGraph" => 3, ... }, zero-count cops omitted.
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

    # RuboCop exits 1 when it finds offences, which is the normal case here — so the exit
    # status is deliberately not checked. What is checked is that the output parses: a run
    # that crashed answers something that is not JSON, and that must not be read as "no
    # offences found".
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
