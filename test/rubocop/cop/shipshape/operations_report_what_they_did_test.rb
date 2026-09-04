# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `records?` answer true reddens every offence test; making it answer false
# reddens the accepted test; making `audit_log_installed?` answer true reddens the test that an
# application without an audit log is left alone — which is the one that matters: nothing is held
# to a thing it never opted into. The gem's suite proves the **templates** record. This is the
class OperationsReportWhatTheyDidTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::OperationsReportWhatTheyDid

  INSTALLED = { "app/shipshape/audit_log.rb" => "module AuditLog\nend\n" }.freeze

  SILENT = <<~RUBY
    class Deed
      def self.call(**arguments)
        new(**arguments).__perform__
      end
    end
  RUBY

  RECORDING = <<~RUBY
    class Deed
      def self.call(**arguments)
        result = new(**arguments).__perform__
        AuditLog.record(operation: name, outcome: :succeeded)
        result
      end
    end
  RUBY

  def test_a_base_class_that_stopped_recording_is_refused
    found = check(SILENT)

    assert_equal 1, found.length
    assert_includes found.first.message, "no longer reports what it did"
  end

  def test_the_offence_carries_the_reason_and_an_example
    message = check(SILENT).first.message

    assert_includes message, "WHY: This base class is every operation of its kind"
    assert_includes message, "INSTEAD:"
    assert_includes message, "outcome: :refused"
  end

  def test_a_base_class_that_records_is_the_shape
    assert_empty check(RECORDING)
  end

  # No `audit_log.rb` beside it means this application has no trail to keep.
  def test_an_application_without_an_audit_log_is_left_alone
    assert_empty offences(SILENT, cop_class: COP, path: "app/shipshape/deed.rb", files: {})
  end

  def test_it_covers_every_operation_that_performs_an_act
    %w[deed io_deed legacy_deed].each do |name|
      assert_equal 1, check(SILENT, "app/shipshape/#{name}.rb").length, name
    end
  end

  def test_a_workflow_is_not_held_to_it
    assert_empty check(SILENT, "app/shipshape/workflow.rb"),
      "**A workflow performs no act**, so it records nothing of its own: each step records what it did, and an entry here would be a second row saying the rows beneath it happened. Holding the installed `workflow.rb` to an audit call made a correct install fail this cop."
  end

  def test_a_question_is_not_held_to_it
    %w[question io_question legacy_question].each do |name|
      assert_empty check(SILENT, "app/shipshape/#{name}.rb"), name
    end
  end

  def test_only_the_installed_base_classes_are_checked
    assert_empty offences(SILENT, cop_class: COP, path: "app/deeds/deed.rb", files: INSTALLED),
      "The base classes are installed under `app/shipshape/`; an application class that happens to be called `deed.rb` elsewhere is not one of them."
  end

  private

  def check(source, path = "app/shipshape/deed.rb")
    offences(source, cop_class: COP, path: path, files: INSTALLED)
  end
end
