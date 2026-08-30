# frozen_string_literal: true

require "pathname"
require "rubocop"

require "shipshape/source_text"
require "shipshape/edges"
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

# `RuboCop::Cop::Base` arrived in RuboCop 1.0 and every cop here subclasses it. Under an
# older RuboCop the requires below fail with a bare NameError that names neither the gem nor
# the reason, so the floor is asserted where it can still be explained.
#
# Supporting 0.x would mean a second cop base class and a second `add_offense` convention —
# two ways to say each thing, in the code whose whole subject is not doing that. An
# application pinned to an old RuboCop runs shipshape from its own bundle instead; see
# "Running against an application that pins an older RuboCop" in the README.
if Gem::Version.new(RuboCop::Version::STRING) < Gem::Version.new("1.0")
  raise Shipshape::Error, "shipshape needs rubocop >= 1.0, found #{RuboCop::Version::STRING}. " \
                          "Run it from its own bundle rather than the application's."
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
require "rubocop/cop/shipshape/workflow_aggregates_permissions"
require "rubocop/cop/shipshape/workflows_branch_on_outcome"
require "rubocop/cop/shipshape/every_door_checks_permission"
require "rubocop/cop/shipshape/operations_are_leaves"
require "rubocop/cop/shipshape/operations_report_what_they_did"
require "rubocop/cop/shipshape/no_entry_point_bypass"
require "rubocop/cop/shipshape/mixins_add_nothing_public"
require "rubocop/cop/shipshape/only_the_door_is_called"
require "rubocop/cop/shipshape/io_is_its_own_kind"
require "rubocop/cop/shipshape/associations_survive_erasure"
require "rubocop/cop/shipshape/commands_prove_idempotence"
require "rubocop/cop/shipshape/personal_data_is_declared"
require "rubocop/cop/shipshape/queries_only_read"

RuboCop::ConfigLoader.default_configuration = RuboCop::ConfigLoader.merge_with_default(
  RuboCop::ConfigLoader.load_file(Shipshape::CONFIG_DEFAULT.to_s),
  Shipshape::CONFIG_DEFAULT.to_s,
)
