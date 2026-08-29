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
require "rubocop/cop/shipshape/no_decisions_in_request_handling"
require "rubocop/cop/shipshape/no_callbacks"
require "rubocop/cop/shipshape/enforcement_messages_are_documentation"
require "rubocop/cop/shipshape/no_type_interrogation"
require "rubocop/cop/shipshape/no_ambient_reads"
require "rubocop/cop/shipshape/no_distant_writes"
require "rubocop/cop/shipshape/typed_arguments"
require "rubocop/cop/shipshape/no_inline_param_parse"
require "rubocop/cop/shipshape/no_unparsed_lookup"
require "rubocop/cop/shipshape/no_nullable_columns"
require "rubocop/cop/shipshape/no_column_defaults"
require "rubocop/cop/shipshape/no_empty_rescue"
require "rubocop/cop/shipshape/no_silent_coercion"
require "rubocop/cop/shipshape/persistence_holds_no_behaviour"
require "rubocop/cop/shipshape/shape_is_composed"
require "rubocop/cop/shipshape/no_generated_interfaces"
require "rubocop/cop/shipshape/operation_declares_permission"
require "rubocop/cop/shipshape/workflow_aggregates_permissions"

RuboCop::ConfigLoader.default_configuration = RuboCop::ConfigLoader.merge_with_default(
  RuboCop::ConfigLoader.load_file(Shipshape::CONFIG_DEFAULT.to_s),
  Shipshape::CONFIG_DEFAULT.to_s,
)
