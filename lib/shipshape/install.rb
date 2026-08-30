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
      shape
      result
      query
      command
      workflow
      io_query
      io_command
      legacy_query
      legacy_command
      typed_params
      operation_surface
    ].freeze

    DIRECTORY = "app/shipshape"

    # **The guards that need the application loaded**, which is why they are tests rather
    # than cops. A cop reads source and cannot see a module included through a variable or a
    # method made by `define_method`; these ask the class itself. They run in the
    # application's own suite, so they are installed rather than shipped.
    TESTS = %w[operations_expose_nothing_test].freeze

    TEST_DIRECTORY = "test/shipshape"

    # Written only when authorisation is asked for. Everything else is written either way.
    AUTH_ONLY = %w[permission].freeze

    # **Authorisation is opt-in, and off by default.** This gem installs into codebases that
    # already run, and base classes demanding an actor on day one would stop every call site
    # at once — which is not a migration, it is an outage. Turn it on when the seam is ready:
    # `shipshape install --auth`. It only ever goes forward from there.
    def initialize(root:, directory: DIRECTORY, test_directory: TEST_DIRECTORY, auth: false)
      @root = typed(root, String)
      @directory = typed(directory, String)
      @test_directory = typed(test_directory, String)
      @auth = typed(auth, Boolean)
    end

    # Answers what it did: { written: [...], skipped: [...] }, both relative paths.
    def call
      report = { written: [], skipped: [] }

      write_into(directory, files, report)
      write_into(test_directory, TESTS, report)

      report
    end

    private

    attr_reader :root, :directory, :test_directory, :auth

    def write_into(folder, names, report)
      FileUtils.mkdir_p(File.join(root, folder))

      names.each do |name|
        relative = File.join(folder, "#{name}.rb")
        target = File.join(root, relative)

        next report[:skipped] << relative if File.exist?(target)

        File.write(target, template(name))
        report[:written] << relative
      end
    end

    def files
      auth ? FILES : FILES - AUTH_ONLY
    end

    def template(name)
      path = File.join(TEMPLATES, "#{name}.rb.tt")
      raise Error, "shipshape: no template for #{name}" unless File.file?(path)

      # `<%- if auth -%>` in a template, and nothing else. Ruby's own `#{}` passes through
      # untouched, so a template stays readable as the file it is about to become.
      ERB.new(File.read(path), trim_mode: "-").result(binding)
    end
  end
end
