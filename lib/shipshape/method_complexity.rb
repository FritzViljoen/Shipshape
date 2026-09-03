# frozen_string_literal: true

require "json"
require "open3"
require "tempfile"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Every method's Assignment Branch Condition size, read back as ordinary `Metrics/AbcSize`
  # offences over `--format json`, the channel `BaseTestClassLines` and `Coupling` also trust.
  class MethodComplexity
    include TypedArguments

    COP = "Metrics/AbcSize"
    DEFAULT_CONFIG = ".rubocop.yml"

    MESSAGE = /\AAssignment Branch Condition size for `(?<method>.+)` is too high\. .*? (?<complexity>[\d.e+-]+)\/[\d.e+-]+\]\z/.freeze

    Method = Struct.new(:file, :name, :line, :complexity, keyword_init: true)

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    def call
      Tempfile.create(["shipshape-method-complexity-", ".yml"]) do |forced|
        forced.write(forced_config)
        forced.flush

        methods_in(JSON.parse(json(forced.path)).fetch("files", []))
      end
    end

    private

    attr_reader :directory, :config

    def methods_in(files)
      files.each_with_object([]) do |file, found|
        path = file.fetch("path").sub(%r{\A\./}, "")

        file.fetch("offenses", []).each do |offence|
          method = method_for(offence)
          found << Method.new(file: path, name: method[:method], line: offence.fetch("location").fetch("start_line"),
                               complexity: Float(method[:complexity])) if method
        end
      end
    end

    def method_for(offence)
      return nil unless offence.fetch("cop_name") == COP

      MESSAGE.match(offence.fetch("message"))
    end

    def forced_config
      lines = []
      lines << "inherit_from: #{inherited_config}" if inherited_config
      lines << "#{COP}:"
      lines << "  Max: 0"
      "#{lines.join("\n")}\n"
    end

    def inherited_config
      return config if config

      default = File.join(directory, DEFAULT_CONFIG)
      default if File.file?(default)
    end

    # Exit 1 is normal, so only the parse is checked: a crash is not "none found".
    def json(forced_config_path)
      out, err, = Open3.capture3(*command(forced_config_path), chdir: directory)
      return out if out.start_with?("{")

      raise Error, "shipshape: could not measure method complexity in #{directory}: #{err.strip}"
    end

    def command(forced_config_path)
      [RbConfig.ruby, rubocop, "--only", COP, "--format", "json", "--no-color",
       "--config", forced_config_path]
    end

    def rubocop
      @rubocop ||= Gem.bin_path("rubocop", "rubocop")
    rescue Gem::Exception
      raise Error, "shipshape: rubocop is not installed in this environment."
    end
  end
end
