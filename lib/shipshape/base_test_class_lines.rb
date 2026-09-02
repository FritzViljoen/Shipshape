# frozen_string_literal: true

require "json"
require "open3"
require "rubocop"
require "rubocop/cop/shipshape/base_test_class_growth"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Every file `Shipshape/BaseTestClassGrowth` visits, sized in lines from that cop's own
  # span offences via `--format json` - the same channel `Offences` already trusts.
  class BaseTestClassLines
    include TypedArguments

    GROWTH_COP = RuboCop::Cop::Shipshape::BaseTestClassGrowth

    def initialize(directory:, config: nil)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
    end

    def call
      spans_by_file.transform_values { |ranges| merge(ranges) }
    end

    private

    attr_reader :directory, :config

    def spans_by_file
      JSON.parse(json).fetch("files", []).each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, grouped|
        path = file.fetch("path").sub(%r{\A\./}, "")

        file.fetch("offenses", []).each do |offence|
          next unless span_offence?(offence)

          location = offence.fetch("location")
          grouped[path] << (location.fetch("start_line")..location.fetch("last_line"))
        end
      end
    end

    def span_offence?(offence)
      offence.fetch("cop_name") == GROWTH_COP.cop_name && offence.fetch("message") == GROWTH_COP::SPAN_MESSAGE
    end

    # Overlapping spans (a module wrapping the class it declares) merge before they are summed.
    def merge(ranges)
      ranges.sort_by(&:first).each_with_object([]) do |range, merged|
        last = merged.last

        if last && range.first <= last.last
          merged[-1] = last.first..[last.last, range.last].max
        else
          merged << range
        end
      end.sum(&:size)
    end

    # Exit 1 is normal, so only the parse is checked: a crash is not "none found".
    def json
      out, err, = Open3.capture3(span_env, *command, chdir: directory)
      return out if out.start_with?("{")

      raise Error, "shipshape: could not measure base test class lines in #{directory}: #{err.strip}"
    end

    # Scoped to this one subprocess, never this process's own `ENV`.
    def span_env
      { GROWTH_COP::RECORD_SPANS_ENV => "1" }
    end

    # `--require` loads the cop regardless of the target's own config.
    def command
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--format", "json", "--no-color"]
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
