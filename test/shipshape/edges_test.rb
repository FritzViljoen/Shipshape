# frozen_string_literal: true

require "test_helper"
require "shipshape/edges"

# Watched to fail: making `covered` always true reddens the uncovered tests; making it always false
# reddens the covered one; removing the empty-actions guard reddens the base-class test. **Asked by
# class, not by method**, and that was measured rather than assumed: a request spec says `get
# "/stories"` and a controller spec says `describe StoriesController`, and almost none of them name
class EdgesTest < Minitest::Test
  SETTINGS = Shipshape::Settings.new(
    kinds: {
      "request_handling" => ["app/controllers/**/*_controller.rb"],
      "entry_point" => ["app/jobs/**/*.rb"],
      "deed" => ["app/deeds/**/*.rb"],
    },
    matrix: { "request_handling" => [], "entry_point" => [], "deed" => [] },
  )

  CONTROLLER = "class StoriesController < ApplicationController\n  def index; end\n\n  def show; end\n\n" \
               "  private\n\n  def helper; end\nend\n"

  def test_an_edge_no_test_names_is_reported
    report = report_for("app/controllers/stories_controller.rb" => CONTROLLER)

    assert_equal 1, report.uncovered.length
    assert_equal %w[index show], report.uncovered.first.actions
    refute_predicate report, :ready?
  end

  def test_a_class_named_in_the_suite_is_covered
    report = report_for(
      "app/controllers/stories_controller.rb" => CONTROLLER,
      "spec/requests/stories_spec.rb" => "RSpec.describe StoriesController do\nend\n",
    )

    assert_empty report.uncovered
    assert_predicate report, :ready?,
      "What a request spec actually contains."
  end

  # The action names are the flattering answer: every suite contains the word "show".
  def test_an_action_name_in_the_suite_is_not_coverage
    report = report_for(
      "app/controllers/stories_controller.rb" => CONTROLLER,
      "spec/unrelated_spec.rb" => "it 'will show and index things' do\nend\n",
    )

    assert_equal 1, report.uncovered.length
  end

  def test_only_the_public_surface_counts
    report = report_for("app/controllers/stories_controller.rb" => CONTROLLER)

    refute_includes report.uncovered.first.actions, "helper",
      "Private helpers are not edges; nothing arrives at them."
  end

  def test_a_base_class_with_no_actions_is_not_an_edge
    report = report_for("app/controllers/application_controller.rb" =>
                        "class ApplicationController < ActionController::Base\nend\n")

    assert_empty report.edges,
      "`ApplicationController` is where an edge inherits from, not an edge."
  end

  def test_jobs_are_edges_too
    report = report_for("app/jobs/notify_job.rb" => "class NotifyJob < ApplicationJob\n  def perform; end\nend\n")

    assert_equal 1, report.edges.length
    assert_equal %w[perform], report.edges.first.actions
  end

  def test_a_deed_is_not_an_edge
    report = report_for("app/deeds/settle.rb" => "class Settle < Deed\n  def call; end\nend\n")

    assert_empty report.edges,
      "A deed is not an edge — nothing arrives from outside at one."
  end

  def test_a_suite_one_level_down_still_counts
    report = report_for(
      "app/controllers/stories_controller.rb" => CONTROLLER,
      "core/spec/requests/stories_spec.rb" => "RSpec.describe StoriesController do\nend\n",
    )

    assert_empty report.uncovered,
      "**A monorepo keeps its suites per engine.** Solidus has `core/spec` and no top-level `spec/`, and looking only at the root reported every one of its 111 edges untested — a false 100%, which sends somebody writing tests that already exist."
  end

  private

  def report_for(files)
    Dir.mktmpdir("edges") do |root|
      files.each do |relative, body|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end

      return Shipshape::Edges.new(root: root, settings: SETTINGS).call
    end
  end
end
