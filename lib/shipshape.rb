# frozen_string_literal: true

require "pathname"
require "rubocop"

require "shipshape/version"
require "shipshape/error"
require "shipshape/boolean"
require "shipshape/typed_arguments"
require "shipshape/settings"
require "shipshape/kinds"

module Shipshape
  CONFIG_DEFAULT = Pathname.new(__dir__).join("..", "config", "default.yml").expand_path
end

require "rubocop/cop/shipshape/call_graph"
require "rubocop/cop/shipshape/one_operation_one_class"

RuboCop::ConfigLoader.default_configuration = RuboCop::ConfigLoader.merge_with_default(
  RuboCop::ConfigLoader.load_file(Shipshape::CONFIG_DEFAULT.to_s),
  Shipshape::CONFIG_DEFAULT.to_s,
)
