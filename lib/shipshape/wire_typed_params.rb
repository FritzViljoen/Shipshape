# frozen_string_literal: true

require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Includes TypedParams into the application's base controller.
  #
  # Writing the file is not enough: a concern nobody includes parses nothing, and the
  # application looks equipped while the seam is open. That is the coverage-shaped hole
  # `a-guard-states-its-limit` exists to close, so the installer closes it rather than
  # printing an instruction and hoping.
  #
  # It is a **separate operation from writing the files**, because it is a different thing:
  # one creates, the other edits something the application already owns.
  #
  # It edits exactly one line and is idempotent — run it twice and the second run reports
  # `:already`. It never rewrites the file wholesale, because a base controller in a legacy
  # application has years of other people's decisions in it.
  class WireTypedParams
    include TypedArguments

    CONTROLLER = "app/controllers/application_controller.rb"
    CONCERN = "TypedParams"
    # `[ \t]*` and not `\s*`: `\s` matches newlines, so a blank line above the class gets
    # eaten into the match and the insertion lands a line too high with the wrong indent.
    CLASS_LINE = /^([ \t]*)class[ \t]+\w+.*$/.freeze

    def initialize(root:, controller: CONTROLLER)
      @root = typed(root, String)
      @controller = typed(controller, String)
    end

    # Answers [outcome, path]: :wired, :already, or :no_controller.
    def call
      return [:no_controller, controller] unless File.file?(path)

      source = File.read(path)
      return [:already, controller] if source.include?("include #{CONCERN}")

      match = source.match(CLASS_LINE)
      return [:no_controller, controller] if match.nil?

      File.write(path, wired(source, match))
      [:wired, controller]
    end

    private

    attr_reader :root, :controller

    def path
      File.join(root, controller)
    end

    # Inserted directly under the class line, indented to match it, so the include is the
    # first thing a reader meets rather than something buried in the middle.
    def wired(source, match)
      indent = "#{match[1]}  "

      source.sub(CLASS_LINE) { "#{match[0]}\n#{indent}include #{CONCERN}" }
    end
  end
end
