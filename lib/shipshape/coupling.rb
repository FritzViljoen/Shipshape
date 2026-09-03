# frozen_string_literal: true

require "set"
require "json"
require "open3"
require "rubocop"
require "rubocop/cop/shipshape/call_graph"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Every call `Shipshape/CallGraph` resolves to two governed kinds, legal or not, plus which
  # files were governed at all - read back as offences over the channel `BaseTestClassLines` uses.
  class Coupling
    include TypedArguments

    CALL_GRAPH_COP = RuboCop::Cop::Shipshape::CallGraph

    # `callee` is nil for a `BaseClasses`-only match, which has no file. `CouplingDelta` reads both.
    Edge = Struct.new(:caller, :callee, keyword_init: true)
    Report = Struct.new(:edges, :governed, keyword_init: true)

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    def call
      files = JSON.parse(json).fetch("files", [])

      Report.new(edges: edges_in(files), governed: governed_files(files))
    end

    private

    attr_reader :directory, :config

    def edges_in(files)
      files.each_with_object([]) do |file, found|
        path = file.fetch("path")

        file.fetch("offenses", []).each do |offence|
          next unless coupling?(offence)

          callee = offence.fetch("message").delete_prefix(CALL_GRAPH_COP::COUPLING_MESSAGE)
          found << Edge.new(caller: path, callee: callee.empty? ? nil : callee)
        end
      end
    end

    def governed_files(files)
      files.each_with_object([]) do |file, found|
        found << file.fetch("path") if file.fetch("offenses", []).any? { |o| message?(o, CALL_GRAPH_COP::GOVERNED_MESSAGE) }
      end.to_set
    end

    def coupling?(offence)
      offence.fetch("cop_name") == CALL_GRAPH_COP.cop_name &&
        offence.fetch("message").start_with?(CALL_GRAPH_COP::COUPLING_MESSAGE)
    end

    def message?(offence, text)
      offence.fetch("cop_name") == CALL_GRAPH_COP.cop_name && offence.fetch("message") == text
    end

    def json
      out, err, = Open3.capture3(coupling_env, *command, chdir: directory)
      return out if out.start_with?("{")

      raise Error, "shipshape: could not measure coupling in #{directory}: #{err.strip}"
    end

    def coupling_env
      { CALL_GRAPH_COP::RECORD_COUPLING_ENV => "1" }
    end

    # An env var never reaches RuboCop's cache key, so this needs its own bucket or it replays
    # `BaseTestClassLines`' cached, marker-free entry - `--display-style-guide` buys that
    # without `--cache false`'s cost to parallelism (see the coupling law's Guard's limit).
    def command
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--format", "json", "--no-color",
                   "--display-style-guide"]
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
