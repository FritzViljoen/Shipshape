# frozen_string_literal: true

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
      entity
      result
      query
      command
      workflow
      legacy_query
      legacy_command
      typed_params
    ].freeze

    DIRECTORY = "app/shipshape"

    def initialize(root:, directory: DIRECTORY)
      @root = typed(root, String)
      @directory = typed(directory, String)
    end

    # Answers what it did: { written: [...], skipped: [...] }, both relative paths.
    def call
      FileUtils.mkdir_p(File.join(root, directory))

      FILES.each_with_object(written: [], skipped: []) do |name, report|
        relative = File.join(directory, "#{name}.rb")
        target = File.join(root, relative)

        next report[:skipped] << relative if File.exist?(target)

        File.write(target, template(name))
        report[:written] << relative
      end
    end

    private

    attr_reader :root, :directory

    def template(name)
      path = File.join(TEMPLATES, "#{name}.rb.tt")
      raise Error, "shipshape: no template for #{name}" unless File.file?(path)

      File.read(path)
    end
  end
end
