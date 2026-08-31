# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `mixin?` answer false reddens every offence test; making `mixin?` answer
# true reddens the shape-concern test, which is the one that matters: the same module is correct
# with public methods when a shape includes it, so a cop that fires on every concern enforces
# something the law does not say; making `public_method?` answer false reddens the method tests;
class MixinsAddNothingPublicTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::MixinsAddNothingPublic

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "command" => ["app/commands/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => { "command" => ["Command"], "shape" => ["Shape"] },
      "Matrix" => { "command" => ["shape"], "shape" => [] },
    },
  }.freeze

  CONFIG = { "OperationKinds" => ["command"] }.freeze

  PATH = "app/models/concerns/paying.rb"

  MIXED_INTO_A_COMMAND = {
    "app/commands/settle_invoice.rb" => "class SettleInvoice < Command\n  include Paying\n\n  def call; end\nend\n",
  }.freeze

  MIXED_INTO_A_SHAPE = {
    "app/shapes/invoice.rb" => "class Invoice < Shape\n  include Paying\nend\n",
  }.freeze

  def test_a_public_method_in_an_operation_mixin_is_refused
    found = check("module Paying\n  def total; end\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`total` is public, and this module is mixed into an operation"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("module Paying\n  def total; end\nend\n").first.message

    assert_includes message, "WHY: An operation exposes `call` and nothing else"
    assert_includes message, "a file none of them mention"
    assert_includes message, "INSTEAD:"
    assert_includes message, "module Paying\n      private"
  end

  def test_the_same_module_is_left_alone_when_only_a_shape_includes_it
    assert_empty check("module Paying\n  def total; end\nend\n", files: MIXED_INTO_A_SHAPE)
  end

  def test_a_module_nobody_includes_is_left_alone
    assert_empty check("module Paying\n  def total; end\nend\n", files: {})
  end

  def test_a_private_method_is_the_shape
    assert_empty check("module Paying\n  private\n\n  def total; end\nend\n")
  end

  def test_a_public_reader_is_a_public_method_in_all_but_name
    found = check("module Paying\n  attr_reader :lines\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "An operation exposes no state"
  end

  # `def self.x` lands on the module object and never travels through `include`.
  def test_a_module_class_method_is_not_this_cops_business
    assert_empty check("module Paying\n  def self.build; end\nend\n")
  end

  def test_a_namespaced_module_matches_the_short_form_written_at_the_include
    found = check("module Billing\n  module Paying\n    def total; end\n  end\nend\n",
                  path: "app/models/concerns/billing/paying.rb")

    assert_equal 1, found.length,
      "An operation inside a namespace writes the short form, and nothing here loads the application to resolve it."
  end

  # A nested module is reached through its parent's name, which is what the operation
  # writes. Judging both would report one module twice.
  def test_a_nested_module_is_judged_once
    assert_equal 1, check("module Paying\n  def total; end\n\n  module Inner\n    def other; end\n  end\nend\n").length
  end

  def test_prepend_counts_as_mixing_in
    files = { "app/commands/settle_invoice.rb" => "class SettleInvoice < Command\n  prepend Paying\nend\n" }

    assert_equal 1, check("module Paying\n  def total; end\nend\n", files: files).length
  end

  private

  def check(source, path: PATH, files: MIXED_INTO_A_COMMAND)
    offences(source, cop_class: COP, cop_config: CONFIG, path: path, files: files,
                     other_cops: LAYOUT)
  end
end
