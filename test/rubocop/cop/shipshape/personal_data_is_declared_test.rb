# frozen_string_literal: true

require "test_helper"

# Watched to fail:
#
# - Emptying `NAMES` reddens every offence test.
# - Making `declared?` answer true reddens them too, and making it answer false reddens the
#   four tests that assert a classified column is accepted — including `:not_personal`, which
#   is the one that keeps this an inventory rather than a suppression list.
#
# **This is not a compliance check and the law says so in as many words.** It makes the
# inventory exist and keeps it from going stale. A green run says every name-matching column
# has been classified by somebody; it says nothing about whether they were right.
class PersonalDataIsDeclaredTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::PersonalDataIsDeclared

  SCHEMA = "db/schema.rb"

  def test_an_unclassified_column_is_refused
    found = check(create_table("t.string \"email\""))

    assert_equal 1, found.length
    assert_includes found.first.message, "`email` looks like it holds something about a person"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(create_table("t.string \"email\"")).first.message

    assert_includes message, "WHY: Erasure is unimplementable without an inventory"
    assert_includes message, "INSTEAD:"
    assert_includes message, ":retain_with_reason"
  end

  # Four answers, and every one of them settles the question.
  def test_a_classified_column_is_accepted
    %w[anonymise delete_row retain_with_reason not_personal].each do |route|
      assert_empty check(create_table("t.string \"email\""), registry(email: route)),
                   "#{route} should settle it"
    end
  end

  # `class_name` matches nothing here; `contact_email` matches by suffix.
  def test_it_matches_a_name_and_a_suffix
    assert_empty check(create_table("t.string \"widget\""))
    assert_equal 1, check(create_table("t.string \"contact_email\"")).length
  end

  def test_add_column_outside_a_table_block_is_read
    assert_equal 1, check("add_column \"users\", \"passport\", :string\n").length
  end

  def test_several_unclassified_columns_are_each_reported
    body = create_table("t.string \"email\"\n    t.string \"passport\"\n    t.string \"widget\"")

    assert_equal 2, check(body).length
  end

  # **A boolean cannot hold a person.** `is_from_email` and `show_email` were two of six
  # findings against two real schemas, and asking somebody to classify a flag is a guard
  # firing on correct code.
  def test_a_boolean_is_never_reported_whatever_it_is_called
    assert_empty check(create_table("t.boolean \"is_from_email\", default: false"))
    assert_empty check(create_table("t.boolean \"show_email\""))
    assert_empty check("add_column \"users\", \"show_email\", :boolean\n")
  end

  # **The registry `shipshape install` writes, verbatim.** Its commented-out examples used to
  # clear `email` and `ip_address` on a fresh install, while `COLUMNS` was genuinely empty —
  # the feature was born blind to the two commonest personal columns and the build was green.
  def test_the_shipped_registry_declares_nothing
    shipped = File.read(File.expand_path("../../../../lib/shipshape/templates/personal_data.rb.tt", __dir__))
    body = create_table("t.string \"email\"\n    t.string \"ip_address\"")

    assert_equal 2, check(body, shipped).length
  end

  # Prose is not a declaration.
  def test_a_comment_naming_a_column_does_not_clear_it
    registry = "module PersonalData\n  # TODO: decide about \"passport\"\n  COLUMNS = {}.freeze\nend\n"

    assert_equal 1, check(create_table("t.string \"passport\""), registry).length
  end

  # **Per table, not per column name.** Classifying `users.email` used to clear `email`
  # everywhere in the schema.
  def test_classifying_one_table_does_not_clear_another
    registry = "module PersonalData\n  COLUMNS = { \"users\" => { \"email\" => :anonymise } }.freeze\nend\n"
    schema = create_table("t.string \"email\"") +
             "create_table \"marketing_leads\" do |t|\n    t.string \"email\"\n  end\n"

    found = check(schema, registry)

    assert_equal 1, found.length
  end

  def test_add_column_is_read_against_its_own_table
    registry = "module PersonalData\n  COLUMNS = { \"users\" => { \"email\" => :anonymise } }.freeze\nend\n"

    assert_empty check("add_column \"users\", \"email\", :string\n", registry)
    assert_equal 1, check("add_column \"leads\", \"email\", :string\n", registry).length
  end

  # The stated limit, pinned so the silence is a decision rather than a discovery.
  def test_a_name_the_list_does_not_know_is_the_stated_blind_spot
    assert_empty check(create_table("t.string \"contact_ref\""))
  end

  private

  def create_table(columns)
    "create_table \"users\" do |t|\n    #{columns}\n  end\n"
  end

  def registry(email:)
    "module PersonalData\n  COLUMNS = { \"users\" => { \"email\" => :#{email} } }.freeze\nend\n"
  end

  def check(schema, registry_source = "module PersonalData\nend\n")
    offences(schema, cop_class: COP, path: SCHEMA,
                     files: { "app/shipshape/personal_data.rb" => registry_source })
  end
end
