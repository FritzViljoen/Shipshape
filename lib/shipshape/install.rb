# frozen_string_literal: true

require "erb"
require "fileutils"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Writes the base classes into an application. Generated, not inherited from this gem — one
  # you can open beats one buried in a dependency. Nothing already written is ever overwritten.
  class Install
    include TypedArguments

    TEMPLATES = File.expand_path("templates", __dir__)

    FILES = %w[
      boolean
      typed_arguments
      permission
      calls
      call_graph
      holds_no_records
      shape
      result
      audit_log
      operation_job
      query
      command
      workflow
      io_query
      io_command
      legacy_query
      legacy_command
      typed_params
      personal_data
      application_view_component
    ].freeze

    DIRECTORY = "app/shipshape"

    # Tests, not cops: a cop reads source and cannot see an include through a variable.
    TESTS = %w[operations_expose_nothing_test personal_data_is_erasable_test].freeze

    TEST_DIRECTORY = "test/shipshape"

    RSPEC_DIRECTORY = "spec/shipshape"

    TASKS = %w[shipshape_routes].freeze

    TASK_DIRECTORY = "lib/tasks"

    AUTH_ONLY = %w[permission calls call_graph].freeze

    # On request only: the one file that can stop a boot, because it inherits from a gem.
    VIEW_COMPONENT_ONLY = %w[application_view_component].freeze

    # Opt-in: demanding an actor on day one stops every call site at once.
    def initialize(root:, directory: DIRECTORY, test_directory: nil, auth: false,
                   view_components: false, rspec: nil)
      @root = typed(root, String)
      @directory = typed(directory, String)
      @auth = typed(auth, Boolean)
      @view_components = typed(view_components, Boolean)
      @rspec = rspec.nil? ? rspec_suite? : typed(rspec, Boolean)
      @test_directory = typed(test_directory || (@rspec ? RSPEC_DIRECTORY : TEST_DIRECTORY), String)
    end

    def call
      report = { written: [], skipped: [], diverged: [], stale: [] }

      write_into(directory, files, report)
      write_into(test_directory, TESTS, report, suffix: rspec ? "_spec" : "_test")
      write_into(TASK_DIRECTORY, auth ? TASKS : [], report, extension: "rake")

      report
    end

    def files
      chosen = FILES
      chosen -= AUTH_ONLY unless auth
      chosen -= VIEW_COMPONENT_ONLY unless view_components
      chosen
    end

    private

    attr_reader :root, :directory, :test_directory, :auth, :view_components, :rspec

    # Detected, never asked: lobsters got two Minitest guards into an all-RSpec suite.
    def rspec_suite?
      return true if Dir.exist?(File.join(root, "spec"))

      gemfile = File.join(root, "Gemfile")
      File.file?(gemfile) && File.read(gemfile).match?(/^\s*gem ["']rspec/)
    end

    def write_into(folder, names, report, extension: "rb", suffix: nil)
      return if names.empty?

      FileUtils.mkdir_p(File.join(root, folder))

      names.each do |name|
        installed = suffix ? name.sub(/_test\z/, suffix) : name
        relative = File.join(folder, "#{installed}.#{extension}")
        target = File.join(root, relative)
        rendered = template(name, extension)

        if File.exist?(target)
          compare(target, relative, rendered, report)
        else
          File.write(target, rendered)
          report[:written] << relative
        end

        note_stale_new(target, relative, report)
      end
    end

    # Nothing to compare against but what this run would write. Identical: silence. Different:
    # this run's version lands beside it as `.new` — diffing here would blend their edits into ours.
    def compare(target, relative, rendered, report)
      return report[:skipped] << relative if File.read(target) == rendered

      File.write("#{target}.new", rendered)
      report[:diverged] << relative
    end

    # A `.new` outlives the divergence that wrote it: once the file matches this run again —
    # edited back by hand, or the gem's version adopted — nothing else ever revisits it.
    def note_stale_new(target, relative, report)
      return if report[:diverged].include?(relative)

      report[:stale] << relative if File.exist?("#{target}.new")
    end

    def template(name, extension = "rb")
      path = File.join(TEMPLATES, "#{name}.#{extension}.tt")
      raise Error, "shipshape: no template for #{name}" unless File.file?(path)

      ERB.new(File.read(path), trim_mode: "-").result(binding)
    end
  end
end
