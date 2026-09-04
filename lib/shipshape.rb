# frozen_string_literal: true

require "pathname"
require "rubocop"

require "shipshape/source_text"
require "shipshape/edges"
require "shipshape/table_shapes"
require "shipshape/test_mentions"
require "shipshape/version"
require "shipshape/error"
require "shipshape/boolean"
require "shipshape/typed_arguments"
require "shipshape/settings"
require "shipshape/kinds"

module Shipshape
  CONFIG_DEFAULT = Pathname.new(__dir__).join("..", "config", "default.yml").expand_path
end

# `RuboCop::Cop::Base` arrived in 1.0, and under an older RuboCop the requires below fail with
# a bare NameError naming neither the gem nor the reason. Supporting 0.x would mean a second
# `add_offense` convention, which is two ways to say one thing; see the README instead.
if Gem::Version.new(RuboCop::Version::STRING) < Gem::Version.new("1.0")
  raise Shipshape::Error, "shipshape needs rubocop >= 1.0, found #{RuboCop::Version::STRING}. " \
                          "Run it from its own bundle rather than the application's."
end

require "rubocop/cop/shipshape/call_graph"
require "rubocop/cop/shipshape/kind_is_inherited_not_only_placed"
require "rubocop/cop/shipshape/one_operation_one_class"
require "rubocop/cop/shipshape/no_decisions_in_request_handling"
require "rubocop/cop/shipshape/no_callbacks"
require "rubocop/cop/shipshape/comment_budget"
require "rubocop/cop/shipshape/presentation_holds_no_records"
require "rubocop/cop/shipshape/presence_is_not_redefined"
require "rubocop/cop/shipshape/enforcement_messages_are_documentation"
require "rubocop/cop/shipshape/no_type_interrogation"
require "rubocop/cop/shipshape/no_ambient_reads"
require "rubocop/cop/shipshape/no_distant_writes"
require "rubocop/cop/shipshape/typed_arguments"
require "rubocop/cop/shipshape/no_inline_param_parse"
require "rubocop/cop/shipshape/no_unparsed_lookup"
require "rubocop/cop/shipshape/absence_is_absence_never_a_value"
require "rubocop/cop/shipshape/no_column_defaults"
require "rubocop/cop/shipshape/no_empty_rescue"
require "rubocop/cop/shipshape/no_silent_coercion"
require "rubocop/cop/shipshape/persistence_holds_no_behaviour"
require "rubocop/cop/shipshape/shape_is_composed"
require "rubocop/cop/shipshape/no_generated_interfaces"
require "rubocop/cop/shipshape/aggregation_is_readable"
require "rubocop/cop/shipshape/workflows_branch_on_outcome"
require "rubocop/cop/shipshape/nothing_schedules_work"
require "rubocop/cop/shipshape/no_test_factories"
require "rubocop/cop/shipshape/anonymity_is_closed_downward"
require "rubocop/cop/shipshape/every_door_checks_permission"
require "rubocop/cop/shipshape/operations_are_leaves"
require "rubocop/cop/shipshape/operations_report_what_they_did"
require "rubocop/cop/shipshape/no_entry_point_bypass"
require "rubocop/cop/shipshape/mixins_add_nothing_public"
require "rubocop/cop/shipshape/only_the_door_is_called"
require "rubocop/cop/shipshape/io_is_its_own_kind"
require "rubocop/cop/shipshape/associations_survive_erasure"
require "rubocop/cop/shipshape/deeds_prove_idempotence"
require "rubocop/cop/shipshape/personal_data_is_declared"
require "rubocop/cop/shipshape/questions_never_write"
require "rubocop/cop/shipshape/operations_open_no_transaction"
require "rubocop/cop/shipshape/no_test_mixins"
require "rubocop/cop/shipshape/base_test_class_growth"

RuboCop::ConfigLoader.default_configuration = RuboCop::ConfigLoader.merge_with_default(
  RuboCop::ConfigLoader.load_file(Shipshape::CONFIG_DEFAULT.to_s),
  Shipshape::CONFIG_DEFAULT.to_s,
)
