# frozen_string_literal: true

require "shipshape/source_text"
require "shipshape/error"
require "shipshape/typed_arguments"

module Shipshape
  # Includes TypedParams into the application's base controller.
  class WireTypedParams
    include TypedArguments

    CONTROLLER = "app/controllers/application_controller.rb"
    CONCERN = "TypedParams"
    # `[ \t]*`, not `\s*`: `\s` eats the blank line above and inserts a line too high.
    CLASS_LINE = /^([ \t]*)class[ \t]+\w+.*$/.freeze

    def initialize(root:, controller: CONTROLLER)
      @root = typed(root, String)
      @controller = typed(controller, String)
    end

    def call
      return [:no_controller, controller] unless File.file?(path)

      source = SourceText.read(path)
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

    def wired(source, match)
      indent = "#{match[1]}  "

      source.sub(CLASS_LINE) { "#{match[0]}\n#{indent}include #{CONCERN}" }
    end
  end
end
