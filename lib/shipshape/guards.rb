# frozen_string_literal: true

require "yaml"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"
require "shipshape/unrecognized_cops"

module Shipshape
  # Which of Shipshape's own cops are switched off in a repository's resolved config.
  class Guards
    include TypedArguments

    DEPARTMENT = "Shipshape"
    TOLERATE_ENV = "SHIPSHAPE_TOLERATE_UNKNOWN_COPS"

    # `--show-cops` never resolves `Enabled: pending`, so a second subprocess asks a live
    # `RuboCop::Config`, built through `RuboCop::ConfigStore` so `--config` resolves exactly
    # the way spawn 1 resolves it, rather than through a hand-mirrored second path.
    PENDING_SCRIPT = <<~'RUBY'
      require "yaml"
      require "rubocop"
      require "shipshape"

      begin
        config_path = ARGV.shift
        RuboCop::ConfigLoader.ignore_unrecognized_cops = true if ENV["SHIPSHAPE_TOLERATE_UNKNOWN_COPS"]
        store = RuboCop::ConfigStore.new
        store.options_config = config_path unless config_path.empty?
        config = store.for_dir(Dir.pwd)
        puts YAML.dump(ARGV.to_h { |name| [name, config.enabled_new_cop?(name)] })
      rescue StandardError => e
        warn "#{e.class}: #{e.message}"
        exit 1
      end
    RUBY

    def initialize(directory:, config: nil, tolerate_unknown_cops: false)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
      @tolerate_unknown_cops = tolerate_unknown_cops
      @skipped_cops = []
    end

    def call
      shipshape = cops.select { |name, _| name.start_with?("#{DEPARTMENT}/") }
      resolved = resolve_pending(shipshape)

      shipshape.each_with_object([]) do |(name, settings), off|
        next unless settings.is_a?(Hash)

        off << name if self.class.disabled?(settings["Enabled"], new_cop_enabled: resolved[name])
      end.sort
    end

    # `false` is disabled outright; `pending` is disabled unless `new_cop_enabled` says otherwise.
    def self.disabled?(enabled, new_cop_enabled: false)
      return true if enabled == false
      return !new_cop_enabled if enabled == "pending"

      false
    end

    # Only meaningful after `call` has run once - see `#yaml`.
    attr_reader :skipped_cops

    private

    attr_reader :directory, :config, :tolerate_unknown_cops

    def cops
      YAML.safe_load(yaml, permitted_classes: [Regexp, Symbol], aliases: true)
    rescue Psych::Exception => e
      raise Error, "shipshape: rubocop --show-cops produced no report in #{directory}: #{e.message}"
    end

    # Exit 0 is normal here, so only the shape is checked: a crash is not "none disabled".
    def yaml
      out, err, = Open3.capture3(*command, chdir: directory)
      @skipped_cops = UnrecognizedCops.named_in(err) if tolerate_unknown_cops
      return out if out.start_with?("#")

      raise Error, "shipshape: rubocop --show-cops produced no report in #{directory}: #{err.strip}"
    end

    def command
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--show-cops", "--no-color"]
      arguments << "--ignore-unrecognized-cops" if tolerate_unknown_cops
      arguments += ["--config", config] if config

      arguments
    end

    def rubocop
      @rubocop ||= Gem.bin_path("rubocop", "rubocop")
    rescue Gem::Exception
      raise Error, "shipshape: rubocop is not installed in this environment."
    end

    # Only pending Shipshape cops need this, so a repo with none pays for no second process.
    def resolve_pending(shipshape)
      pending = shipshape.select { |_, settings| settings.is_a?(Hash) && settings["Enabled"] == "pending" }.keys
      return {} if pending.empty?

      env = tolerate_unknown_cops ? { TOLERATE_ENV => "1" } : {}
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", PENDING_SCRIPT, "--", config.to_s, *pending,
                                         chdir: directory)
      raise Error, "shipshape: could not resolve NewCops in #{directory}: #{err.strip}" unless status.success?

      YAML.safe_load(out, permitted_classes: [Symbol]) || {}
    end
  end
end
