# frozen_string_literal: true

require "erb"
require "fileutils"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Writes the base classes into an application. Generated, not inherited from this gem: one you
  # can open beats one buried in a dependency, and it keeps shipshape a development dependency.
  # They land in `app/shipshape/` because a base class is not an instance of what it defines.
  # Nothing is ever overwritten — once written, a file is the application's.
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

    TASKS = %w[shipshape_routes].freeze

    TASK_DIRECTORY = "lib/tasks"

      AUTH_ONLY = %w[permission calls call_graph].freeze

    # On request only: the one file that can stop a boot, because it inherits from a gem.
    VIEW_COMPONENT_ONLY = %w[application_view_component].freeze

    # Opt-in: demanding an actor on day one stops every call site at once.
    def initialize(root:, directory: DIRECTORY, test_directory: TEST_DIRECTORY, auth: false,
                   view_components: false)
      @root = typed(root, String)
      @directory = typed(directory, String)
      @test_directory = typed(test_directory, String)
      @auth = typed(auth, Boolean)
      @view_components = typed(view_components, Boolean)
    end

      def call
      report = { written: [], skipped: [] }

      write_into(directory, files, report)
      write_into(test_directory, TESTS, report)
      write_into(TASK_DIRECTORY, auth ? TASKS : [], report, extension: "rake")

      report
    end

    private

    attr_reader :root, :directory, :test_directory, :auth, :view_components

    def write_into(folder, names, report, extension: "rb")
      return if names.empty?

      FileUtils.mkdir_p(File.join(root, folder))

      names.each do |name|
        relative = File.join(folder, "#{name}.#{extension}")
        target = File.join(root, relative)

        next report[:skipped] << relative if File.exist?(target)

        File.write(target, template(name, extension))
        report[:written] << relative
      end
    end

    def files
      chosen = FILES
      chosen -= AUTH_ONLY unless auth
      chosen -= VIEW_COMPONENT_ONLY unless view_components
      chosen
    end

    def template(name, extension = "rb")
      path = File.join(TEMPLATES, "#{name}.#{extension}.tt")
      raise Error, "shipshape: no template for #{name}" unless File.file?(path)

      ERB.new(File.read(path), trim_mode: "-").result(binding)
    end
  end
end
