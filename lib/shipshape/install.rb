# frozen_string_literal: true

require "erb"
require "fileutils"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Writes the base classes into an application.
  #
  # **They are generated, not inherited from this gem.** A base class you can open in your
  # own repository beats one buried in a dependency — that is `nothing-is-hidden` — and it
  # keeps shipshape a development dependency rather than something the application loads in
  # production.
  #
  # They land in `app/shipshape/` rather than in the governed trees, because a base class
  # is not an instance of the thing it defines: `Command` is not a command. Rails autoloads
  # every directory under `app/`, so the constants resolve without configuration.
  #
  # **Nothing is ever overwritten.** Once written, a file is the application's, and the
  # installer reports what it skipped rather than deciding for anybody.
  class Install
    include TypedArguments

    TEMPLATES = File.expand_path("templates", __dir__)

    # Ordered by what depends on what, so a reader following them top to bottom meets each
    # name before it is used.
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

    # **The guards that need the application loaded**, which is why they are tests rather
    # than cops. A cop reads source and cannot see a module included through a variable or a
    # method made by `define_method`; these ask the class itself. They run in the
    # application's own suite, so they are installed rather than shipped.
    TESTS = %w[operations_expose_nothing_test personal_data_is_erasable_test].freeze

    TEST_DIRECTORY = "test/shipshape"

    # **A rake task, because it has to run inside the application.** The routes and the loaded
    # operation classes are both Rails', so nothing outside the app can assemble this table.
    TASKS = %w[shipshape_routes].freeze

    TASK_DIRECTORY = "lib/tasks"

    # Written only when authorisation is asked for. Everything else is written either way.
    AUTH_ONLY = %w[permission calls call_graph].freeze

    # **Written only on request, because it is the one file that can stop a boot.** It
    # inherits from the `view_component` gem, and an application without that gem cannot load
    # it. Everything else here is a PORO that loads anywhere.
    VIEW_COMPONENT_ONLY = %w[application_view_component].freeze

    # **Authorisation is opt-in, and off by default.** This gem installs into codebases that
    # already run, and base classes demanding an actor on day one would stop every call site
    # at once — which is not a migration, it is an outage. Turn it on when the seam is ready:
    # `shipshape install --auth`. It only ever goes forward from there.
    def initialize(root:, directory: DIRECTORY, test_directory: TEST_DIRECTORY, auth: false,
                   view_components: false)
      @root = typed(root, String)
      @directory = typed(directory, String)
      @test_directory = typed(test_directory, String)
      @auth = typed(auth, Boolean)
      @view_components = typed(view_components, Boolean)
    end

    # Answers what it did: { written: [...], skipped: [...] }, both relative paths.
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

      # `<%- if auth -%>` in a template, and nothing else. Ruby's own `#{}` passes through
      # untouched, so a template stays readable as the file it is about to become.
      ERB.new(File.read(path), trim_mode: "-").result(binding)
    end
  end
end
