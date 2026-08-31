# frozen_string_literal: true

require "shipshape/source_text"
require "shipshape/test_mentions"
require "json"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # The work, one file at a time, in an order that is safe to start. An agent handed a whole
  # codebase does the wrong thing: it needs one file, the rules it breaks, and a way to know it
  # finished. Each unit carries the full offence messages, which are the prompt. Covered files
  # come first — not because they are worse, because nothing here proves behaviour is preserved.
  class Queue
    include TypedArguments

    Unit = Struct.new(:path, :offences, :cops, :tested, :methods, :unnamed, keyword_init: true) do
      def to_h
        { path: path, tested: tested, methods: methods, unnamed_in_tests: unnamed,
          cops: cops, offences: offences }
      end

      def covered
        methods - unnamed.length
      end
    end

    TEST_DIRECTORIES = %w[test spec].freeze

    def initialize(root: Dir.pwd, config: nil, targets: %w[app lib])
      @root = typed(root, String)
      @config = typed(config, String, allow_nil: true)
      @targets = targets
    end

    def call(limit: 5)
      units = report.filter_map { |file| unit_for(file) }

      ranked(units).first(limit)
    end

    private

    attr_reader :root, :config, :targets

    # Best covered first, then most rules broken. A boolean put one covered method of eighty
    # ahead of nine of nine: the ratio says how much can move while the work stays verifiable.
    def ranked(units)
      units.sort_by do |unit|
        [-coverage(unit), -unit.cops.length, -unit.offences.length, unit.path]
      end
    end

    def coverage(unit)
      return 0.0 if unit.methods.zero?

      unit.covered.to_f / unit.methods
    end

    def unit_for(file)
      return if file["offenses"].empty?

      path = file["path"].sub(%r{\A#{Regexp.escape(root)}/}, "")
      offences = file["offenses"].map do |offence|
        { cop: offence["cop_name"], line: offence.dig("location", "line"), message: offence["message"] }
      end

      defined = methods_in(path)
      unnamed = defined.reject { |method| named_in_a_test?(method) }

      Unit.new(path: path, offences: offences,
               cops: offences.map { |o| o[:cop] }.uniq.sort,
               tested: defined.any? && unnamed.length < defined.length,
               methods: defined.length, unnamed: unnamed.sort)
    end

    # Per method: "story.rb has a test" says nothing about the method you are about to move. A
    # name match, not a call graph — it answers "would anything notice".
    DEFINITION = /^\s*def (?:self\.)?([a-z_][\w]*[?!=]?)/.freeze

    def methods_in(path)
      read(File.join(root, path)).scan(DEFINITION).flatten.uniq
                                 .reject { |method| mentions.too_common?(method) }
    end

    def named_in_a_test?(method)
      mentions.names?(method)
    end

    def mentions
      @mentions ||= TestMentions.new(root: root)
    end

    def read(file)
      SourceText.read(file)
    rescue SystemCallError => e
      raise Error, "shipshape: cannot read #{file.sub("#{root}/", '')} — #{e.class}"
    end

    def report
      @report ||= begin
        command = [RbConfig.ruby, "-I", File.expand_path("../..", __dir__) + "/lib", rubocop,
                   "--require", "shipshape", "--only", "Shipshape",
                   "--format", "json", "--no-color"]
        command += ["--config", config] if config
        command += targets.select { |target| Dir.exist?(File.join(root, target)) }

        out, err, = Open3.capture3(*command, chdir: root)
        json = out[/\{.*\}/m]
        raise Error, "shipshape: rubocop produced no report: #{err.strip}" unless json

        JSON.parse(json)["files"]
      end
    end

    def rubocop
      @rubocop ||= Gem.bin_path("rubocop", "rubocop")
    rescue Gem::Exception
      raise Error, "shipshape: rubocop is not installed in this environment."
    end
  end
end
