# frozen_string_literal: true

require "set"
require "json"
require "open3"
require "rubocop"
require "rubocop/cop/shipshape/call_graph"
require "shipshape/config_at"
require "shipshape/error"
require "shipshape/kinds"
require "shipshape/settings"
require "shipshape/typed_arguments"
require "shipshape/unrecognized_cops"

module Shipshape
  # Every call `Shipshape/CallGraph` resolves to two governed kinds, legal or not — governance
  # and a callee's path both resolved per-file, honouring a nested config, then reported
  # relative to `directory` throughout. See the coupling law.
  class Coupling
    include TypedArguments

    CALL_GRAPH_COP = RuboCop::Cop::Shipshape::CallGraph

    # `callee` is nil for a `BaseClasses`-only match, which has no file. `CouplingDelta` reads both.
    Edge = Struct.new(:caller, :callee, keyword_init: true)
    Report = Struct.new(:edges, :governed, :skipped_cops, keyword_init: true) # see `ConfigAt`

    def initialize(directory:, config: nil, tolerate_unknown_cops: false)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
      @tolerate_unknown_cops = tolerate_unknown_cops
      @skipped_cops = Set.new
    end

    def call
      files = JSON.parse(json).fetch("files", [])

      Report.new(edges: edges_in(files), governed: governed_files, skipped_cops: skipped_cops.to_a.sort)
    end

    private

    attr_reader :directory, :config, :tolerate_unknown_cops, :skipped_cops

    def edges_in(files)
      files.each_with_object([]) do |file, found|
        path = file.fetch("path").sub(%r{\A\./}, "")

        file.fetch("offenses", []).each do |offence|
          next unless coupling?(offence)

          callee = offence.fetch("message").delete_prefix(CALL_GRAPH_COP::COUPLING_MESSAGE)
          found << Edge.new(caller: path, callee: callee.empty? ? nil : callee_path(path, callee))
        end
      end
    end

    def coupling?(offence)
      offence.fetch("cop_name") == CALL_GRAPH_COP.cop_name &&
        offence.fetch("message").start_with?(CALL_GRAPH_COP::COUPLING_MESSAGE)
    end

    # A nested config can shift the caller's own base dir away from `directory` - re-resolve
    # against it, then report relative to `directory` like every other path here.
    def callee_path(caller_relative, callee_relative_to_caller_base)
      caller_dir = File.dirname(File.join(directory, caller_relative))
      base = config_at(caller_dir).base_dir_for_path_parameters
      relative_to_directory(File.join(base, callee_relative_to_caller_base))
    end

    def governed_files
      config_dirs.flat_map { |dir| governed_under(dir) }.to_set
    end

    # `directory`, plus anywhere a nested `.rubocop.yml` shifts the config - the same gap `callee_path` closes.
    def config_dirs
      ([directory] + Dir.glob(File.join(directory, "**", ".rubocop.yml")).map { |f| File.dirname(f) }).uniq
    end

    def governed_under(dir)
      config = config_at(dir)
      base = config.base_dir_for_path_parameters

      Kinds.new(settings: Settings.layout(config), base_dir: base)
           .governed_files
           .map { |relative| relative_to_directory(File.join(base, relative)) }
    end

    def relative_to_directory(absolute_path)
      full = File.expand_path(absolute_path)
      prefix = "#{File.expand_path(directory)}/"
      full.start_with?(prefix) ? full[prefix.length..-1] : full
    end

    # Same lookup as `Check#config_at`, both now routed through `ConfigAt`.
    def config_at(dir)
      result = ConfigAt.call(dir, config: config, tolerate_unknown_cops: tolerate_unknown_cops)
      skipped_cops.merge(result.skipped_cops)
      result.config
    end

    def json
      out, err, = Open3.capture3(coupling_env, *command, chdir: directory)
      skipped_cops.merge(UnrecognizedCops.named_in(err)) if tolerate_unknown_cops
      return out if out.start_with?("{")

      raise Error, "shipshape: could not measure coupling in #{directory}: #{err.strip}"
    end

    def coupling_env
      { CALL_GRAPH_COP::RECORD_COUPLING_ENV => "1" }
    end

    # `--display-style-guide` buys a cache bucket of its own without `--cache false`'s cost.
    def command
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--format", "json", "--no-color",
                   "--display-style-guide"]
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
