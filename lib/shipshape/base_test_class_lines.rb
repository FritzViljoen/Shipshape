# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Every file `Shipshape/BaseTestClassGrowth` visits, and its qualifying bodies' merged size
  # in lines - read back from that cop's own investigation, never a second walk of the AST.
  class BaseTestClassLines
    include TypedArguments

    FORMATTER = "RuboCop::Formatter::ShipshapeTestClassSizes"

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    def call
      JSON.parse(json)
    end

    private

    attr_reader :directory, :config

    def json
      Dir.mktmpdir("shipshape-sizes") do |tmp|
        out = File.join(tmp, "sizes.json")
        _out, err, = Open3.capture3(*command(out), chdir: directory)
        content = File.exist?(out) ? File.read(out) : ""

        return content if content.start_with?("{")

        raise Error, "shipshape: could not measure base test class lines in #{directory}: #{err.strip}"
      end
    end

    # `--require` loads the formatter itself - a target's own config may never say
    # `require: shipshape`, and naming an unresolved class in `--format` crashes.
    def command(out)
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--format", FORMATTER,
                   "--out", out, "--no-color"]
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
