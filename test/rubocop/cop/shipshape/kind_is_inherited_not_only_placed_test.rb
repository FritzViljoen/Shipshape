# frozen_string_literal: true

require "test_helper"

# Watched to fail: skipping the nil-parent branch reddens the bare-class test; `false`
# instead of `nil` for an unresolved name reddens every "left alone" test.
class KindIsInheritedNotOnlyPlacedTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::KindIsInheritedNotOnlyPlaced

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "deed" => ["app/deeds/**/*.rb"],
        "shape" => ["app/shapes/**/*.rb"],
      },
      "BaseClasses" => { "deed" => %w[Deed ApplicationMailer] },
      "Matrix" => { "deed" => ["shape"], "shape" => [] },
    },
  }.freeze

  DEED = "app/deeds/settle_invoice.rb"

  def test_a_bare_class_with_no_superclass_is_an_offence
    found = check("class SettleInvoice\n  def call; end\nend\n")

    assert_equal 1, found.length
    assert_includes found.first.message, "`SettleInvoice` is a deed by placement, and " \
                                          "names no superclass at all"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check("class SettleInvoice\nend\n").first.message

    assert_includes message, "WHY: Every cop gated on `deed` assumes"
    assert_includes message, "INSTEAD:"
    assert_includes message, "class SettleInvoice < Deed"
  end

  def test_inheriting_the_declared_base_directly_is_the_shape
    assert_empty check("class SettleInvoice < Deed\n  def call; end\nend\n")
  end

  def test_inheriting_a_base_transitively_through_a_governed_file_is_the_shape
    found = offences(
      "class SettleInvoice < AdminDeed\n  def call; end\nend\n",
      cop_class: COP, path: DEED, other_cops: LAYOUT,
      files: { "app/deeds/admin_deed.rb" => "class AdminDeed < Deed\nend\n" },
    )

    assert_empty found
  end

  # A chain fully traced to a real file, proven never to reach `Deed`.
  def test_inheriting_a_fully_resolved_chain_that_never_reaches_the_base_is_an_offence
    found = offences(
      "class SettleInvoice < AdminDeed\n  def call; end\nend\n",
      cop_class: COP, path: DEED, other_cops: LAYOUT,
      files: { "app/deeds/admin_deed.rb" => "class AdminDeed\nend\n" },
    )

    assert_equal 1, found.length
    assert_includes found.first.message,
                    "neither `AdminDeed` nor anything it inherits is `Deed`"
  end

  # A gem base this canon never installed and cannot find on disk.
  def test_a_superclass_this_canon_cannot_resolve_is_left_alone
    found = check("class SettleInvoice < Devise::SessionsController\n  def call; end\nend\n")

    assert_empty found
  end

  # `app/shipshape/` sits outside every `Kinds` glob, so a base filed there is unresolvable.
  def test_a_base_installed_outside_every_kind_is_left_alone
    found = offences(
      "class SettleInvoice < AuthenticatedDeed\n  def call; end\nend\n",
      cop_class: COP, path: DEED, other_cops: LAYOUT,
      files: { "app/shipshape/authenticated_deed.rb" => "class AuthenticatedDeed < Deed\nend\n" },
    )

    assert_empty found
  end

  # A superclass assigned through a constant is invisible to a static resolver by construction.
  def test_a_superclass_assigned_through_a_constant_is_left_alone
    found = check(<<~RUBY)
      BASE = Deed
      class SettleInvoice < BASE
        def call; end
      end
    RUBY

    assert_empty found
  end

  # `shape` names no BaseClasses entry in this layout: left alone rather than guessed at.
  def test_a_kind_with_no_declared_base_is_left_alone
    found = offences("class Basket\nend\n", cop_class: COP, path: "app/shapes/basket.rb",
                                            other_cops: LAYOUT)

    assert_empty found
  end

  # `an-operation-is-a-leaf` names the same shape: a base class filed beside its own kind is
  # still a base class, and it cannot inherit itself.
  def test_the_base_class_filed_beside_its_own_kind_is_exempt
    found = offences("class Deed\nend\n", cop_class: COP, path: "app/deeds/deed.rb",
                                             other_cops: LAYOUT)

    assert_empty found
  end

  def test_a_sibling_class_in_the_same_file_is_left_alone
    found = check(<<~RUBY)
      class SettleInvoiceError < StandardError
      end

      class SettleInvoice < Deed
        def call; end
      end
    RUBY

    assert_empty found
  end

  def test_a_nested_helper_class_is_left_alone
    found = check(<<~RUBY)
      class SettleInvoice < Deed
        class Helper
        end

        def call; end
      end
    RUBY

    assert_empty found
  end

  # A `workflow` firing must show `Workflow`, never the old fixed `Deed` example.
  def test_the_example_names_the_firing_kind_own_declared_base
    layout = {
      "Shipshape/CallGraph" => {
        "Kinds" => { "workflow" => ["app/workflows/**/*.rb"] },
        "BaseClasses" => { "workflow" => ["Workflow"] },
        "Matrix" => { "workflow" => [] },
      },
    }
    found = offences("class SettleOrder\nend\n", cop_class: COP,
                                                  path: "app/workflows/settle_order.rb", other_cops: layout)

    assert_includes found.first.message, "class SettleOrder < Workflow"
    refute_includes found.first.message, "class SettleInvoice < Deed"
  end

  # A kind this cop's own example hash never anticipated: bare `fetch` would raise `KeyError`.
  def test_a_kind_this_cop_does_not_recognise_falls_back_to_the_generic_example
    layout = {
      "Shipshape/CallGraph" => {
        "Kinds" => { "legacy_door" => ["app/doors/**/*.rb"] },
        "BaseClasses" => { "legacy_door" => ["LegacyDoor"] },
        "Matrix" => { "legacy_door" => [] },
      },
    }
    found = offences("class OldReport\nend\n", cop_class: COP,
                                               path: "app/doors/old_report.rb", other_cops: layout)

    assert_includes found.first.message, "class Example < LegacyDoor"
  end

  # No declared base resolves a real gap; a subscriber naming none stays a true positive.
  def test_a_subscriber_inheriting_nothing_is_still_an_offence
    layout = {
      "Shipshape/CallGraph" => {
        "Kinds" => { "entry_point" => ["app/subscribers/**/*.rb"] },
        "BaseClasses" => { "entry_point" => ["ApplicationJob"] },
        "Matrix" => { "entry_point" => [] },
      },
    }
    found = offences("class BookingCreatedSubscriber\nend\n", cop_class: COP,
                      path: "app/subscribers/booking_created_subscriber.rb", other_cops: layout)

    assert_equal 1, found.length
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: DEED, other_cops: LAYOUT)
  end
end
