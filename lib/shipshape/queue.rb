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

    Unit = Struct.new(:path, :offences, :cops, :tested, :methods, :unnamed, keyword_init: true) do
      def to_h
        { path: path, tested: tested, methods: methods, unnamed_in_tests: unnamed,
          cops: cops, offences: offences }
      end

      # Nothing here proves behaviour is preserved. This is the nearest a static tool gets:
      # which of this file's methods are named by a test at all.
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

    # **Best covered first**, then whatever breaks the most different rules — a file with six
    # kinds of finding is six problems, and a file with sixty of one kind is one problem
    # repeated. A boolean put a file with one covered method of eighty ahead of one with all
    # nine covered, which is the wrong way round: the ratio is what says how much of the file
    # can be moved before the work stops being verifiable.
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

    # **Per method, not per file.** A file-level answer is nearly useless: `story.rb` has a
    # test, and that says nothing about the method you are about to move. What an agent
    # needs is which methods are named somewhere in the suite, so it can extract those first
    # and leave the rest until something covers them.
    #
    # This is a name match, not a call graph. A method named in a comment counts, and a
    # method called through `send` does not — it answers "would anything notice", which is
    # the question, and a precise answer would mean running the suite.
    DEFINITION = /^\s*def (?:self\.)?([a-z_][\w]*[?!=]?)/.freeze

    # Ruby's own vocabulary, and the words every test file contains anyway. Matching these
    # would mark every method covered.
    TOO_COMMON = %w[
      initialize call to_s to_h to_a inspect each map new name id type value
      first last count length size empty? present? blank? nil? key? include?
    ].freeze

    def methods_in(path)
      File.read(File.join(root, path)).scan(DEFINITION).flatten.uniq - TOO_COMMON
    rescue StandardError
      []
    end

    def named_in_a_test?(method)
      bare = method.sub(/[?!=]\z/, "")
      return false if bare.length < 4

      test_source.include?(bare)
    end

    # Read once. A grep per method over a large suite is minutes, and this runs per file.
    def test_source
      @test_source ||= TEST_DIRECTORIES.flat_map { |directory|
        Dir.glob(File.join(root, directory, "**", "*.rb"))
      }.map { |file| File.read(file) rescue "" }.join("\n")
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
