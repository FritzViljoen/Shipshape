# frozen_string_literal: true

require "json"
require "open3"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # **The work, one file at a time, in an order that is safe to start.**
  #
  # The report says where the reading is expensive. This says what to do next, and it exists
  # because an agent handed a whole codebase does the wrong thing: it needs one file, the
  # rules that file breaks, and a way to know it finished.
  #
  # Each unit carries the **full offence messages**, not a summary. Those messages are the
  # prompt — each one states the rule, why it exists, and a correct example — so a unit is
  # actionable with nothing else loaded.
  #
  # **Files with a test that names them come first.** Not because they are worse, because
  # they are safe: the ratchet proves the offence count fell, and nothing in this gem proves
  # the code still works. Extracting a rule out of a class nothing tests is how a refactor
  # becomes an outage, so the queue puts the covered work first and says so on the rest.
  class Queue
    include TypedArguments

    Unit = Struct.new(:path, :offences, :cops, :tested, keyword_init: true) do
      def to_h
        { path: path, tested: tested, cops: cops, offences: offences }
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

    # Covered first, then whatever breaks the most different rules — a file with six kinds of
    # finding is six problems, and a file with sixty of one kind is one problem repeated.
    def ranked(units)
      units.sort_by { |unit| [unit.tested ? 0 : 1, -unit.cops.length, -unit.offences.length, unit.path] }
    end

    def unit_for(file)
      return if file["offenses"].empty?

      path = file["path"].sub(%r{\A#{Regexp.escape(root)}/}, "")
      offences = file["offenses"].map do |offence|
        { cop: offence["cop_name"], line: offence.dig("location", "line"), message: offence["message"] }
      end

      Unit.new(path: path, offences: offences,
               cops: offences.map { |o| o[:cop] }.uniq.sort, tested: tested?(path))
    end

    # A test file that names the class. Crude on purpose: it answers "is there anything at
    # all that would notice", which is the question, and a precise answer would need to run
    # the suite.
    def tested?(path)
      constant = File.basename(path, ".rb")
      return false if constant.empty?

      TEST_DIRECTORIES.any? do |directory|
        Dir.glob(File.join(root, directory, "**", "*#{constant}*")).any?
      end
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
