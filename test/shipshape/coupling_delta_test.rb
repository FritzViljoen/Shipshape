# frozen_string_literal: true

require "test_helper"
require "shipshape/coupling_delta"

# Pure arithmetic over `Coupling::Report`s built by hand - no subprocess, no RuboCop.
class CouplingDeltaTest < Minitest::Test
  Edge = Shipshape::Coupling::Edge

  def test_an_edge_unchanged_on_both_ends_is_stable
    base = report(edges: [Edge.new(caller: "a.rb", callee: "b.rb")], governed: %w[a.rb b.rb])
    head = report(edges: [Edge.new(caller: "a.rb", callee: "b.rb")], governed: %w[a.rb b.rb])

    totals = delta(base, head)

    assert_equal 1, totals.was
    assert_equal 1, totals.now
    assert_equal 0, totals.arrived_edges
    assert_equal 0, totals.left_edges
  end

  def test_a_cut_edge_falls_and_nothing_arrives_or_leaves
    base = report(edges: [Edge.new(caller: "a.rb", callee: "b.rb")], governed: %w[a.rb b.rb])
    head = report(edges: [], governed: %w[a.rb b.rb])

    totals = delta(base, head)

    assert_equal 1, totals.was
    assert_equal 0, totals.now
    assert_equal 0, totals.arrived_edges
    assert_equal 0, totals.left_edges
  end

  # The reviewer's case B: a cut alongside a big file arriving under governance.
  def test_a_cut_and_an_arriving_file_are_reported_separately
    base = report(
      edges: [Edge.new(caller: "app/commands/create_person.rb", callee: "app/queries/list_people.rb")] * 2,
      governed: %w[app/commands/create_person.rb app/queries/list_people.rb],
    )
    head = report(
      edges: [Edge.new(caller: "app/commands/create_person.rb", callee: "app/queries/list_people.rb")] +
             [Edge.new(caller: "app/commands/big.rb", callee: "app/queries/list_people.rb")] * 3,
      governed: %w[app/commands/create_person.rb app/queries/list_people.rb app/commands/big.rb],
    )

    totals = delta(base, head)

    assert_equal 2, totals.was
    assert_equal 1, totals.now, "the stable ratchet still falls - the real cut is not hidden by the arrival"
    assert_equal 3, totals.arrived_edges
    assert_equal 1, totals.arrived_files
    assert_equal 0, totals.left_edges
    assert_equal 0, totals.left_files
  end

  # The detangling slice: only the callee arrives under governance, no call site touched.
  def test_a_callee_arriving_under_governance_is_flat_not_a_rise
    base = report(edges: [], governed: %w[app/commands/create_person.rb])
    head = report(
      edges: [Edge.new(caller: "app/commands/create_person.rb", callee: "app/queries/list_people.rb")],
      governed: %w[app/commands/create_person.rb app/queries/list_people.rb],
    )

    totals = delta(base, head)

    assert_equal 0, totals.was
    assert_equal 0, totals.now, "the callee's arrival is not a rise the caller is billed for"
    assert_equal 1, totals.arrived_edges
    assert_equal 1, totals.arrived_files
  end

  # A file deleted, or moved out of a governed glob, shows as `left`, never as a fall.
  def test_a_file_leaving_governance_reports_left_not_a_fall
    base = report(
      edges: [Edge.new(caller: "app/commands/old_thing.rb", callee: "app/queries/list_people.rb")],
      governed: %w[app/commands/old_thing.rb app/queries/list_people.rb],
    )
    head = report(edges: [], governed: %w[app/queries/list_people.rb])

    totals = delta(base, head)

    assert_equal 0, totals.was
    assert_equal 0, totals.now
    assert_equal 1, totals.left_edges
    assert_equal 1, totals.left_files
  end

  # A nil callee - `BaseClasses` alone - can never disqualify an edge as arrived or left.
  def test_an_edge_to_a_base_class_with_no_file_is_always_stable
    base = report(edges: [Edge.new(caller: "app/records/thing_record.rb", callee: nil)],
                  governed: %w[app/records/thing_record.rb])
    head = report(edges: [Edge.new(caller: "app/records/thing_record.rb", callee: nil)],
                  governed: %w[app/records/thing_record.rb])

    totals = delta(base, head)

    assert_equal 1, totals.was
    assert_equal 1, totals.now
    assert_equal 0, totals.arrived_edges
    assert_equal 0, totals.left_edges
  end

  private

  def report(edges:, governed:)
    Shipshape::Coupling::Report.new(edges: edges, governed: governed.to_set)
  end

  def delta(base, head)
    Shipshape::CouplingDelta.new(base: base, head: head).call
  end
end
