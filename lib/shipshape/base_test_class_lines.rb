# frozen_string_literal: true

require "json"
require "open3"
require "rubocop"
require "rubocop/cop/shipshape/base_test_class_growth"
require "shipshape/error"
require "shipshape/typed_arguments"
require "shipshape/unrecognized_cops"

module Shipshape
  # Every file `Shipshape/BaseTestClassGrowth` visits, sized in lines from that cop's own
  # span offences via `--format json` - the same channel `Offences` already trusts.
  class BaseTestClassLines
    include TypedArguments

    GROWTH_COP = RuboCop::Cop::Shipshape::BaseTestClassGrowth

    def initialize(directory:, config: nil, tolerate_unknown_cops: false)
      @directory = typed(directory, String)
      @config = typed(config, String, allow_nil: true)
      @tolerate_unknown_cops = tolerate_unknown_cops
      @skipped_cops = []
    end

    def call
      spans_by_file.transform_values { |ranges| merge(ranges) }
    end

    attr_reader :skipped_cops

    private

    attr_reader :directory, :config, :tolerate_unknown_cops

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
      @skipped_cops = UnrecognizedCops.named_in(err) if tolerate_unknown_cops
      return out if out.start_with?("{")

      raise Error, "shipshape: could not measure base test class lines in #{directory}: #{err.strip}"
    end

    # Scoped to this one subprocess, never this process's own `ENV`.
    def span_env
      { GROWTH_COP::RECORD_SPANS_ENV => "1" }
    end

    # `--extra-details` buys a cache bucket of its own, distinct from `Coupling`'s own marker,
    # and appends nothing to this cop's message, so `span_offence?`'s exact match still holds.
    def command
      arguments = [RbConfig.ruby, rubocop, "--require", "shipshape", "--format", "json", "--no-color",
                   "--extra-details"]
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
