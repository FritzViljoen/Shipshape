# frozen_string_literal: true

require "test_helper"
require "shipshape/queue"

# Watched to fail, as `a-guard-states-its-limit` requires:
#
# - Removing the `tested` term from `ranked` reddens the covered-first test.
# - Removing the `-unit.cops.length` term reddens the distinct-rules test.
# - Making `tested?` answer true reddens the untested-warning test.
#
# The ordering is the whole product here. A queue that offers an untested god class first is
# a queue that turns a refactor into an outage, and nothing in this gem would notice.
class QueueTest < Minitest::Test
  LAYOUT = <<~YAML
    inherit_from:
      - #{Shipshape::CONFIG_DEFAULT}

    AllCops:
      NewCops: disable
      SuggestExtensions: false
  YAML

  # Two rules broken, and a test names it.
  COVERED = <<~RUBY
    class CoveredRecord < ApplicationRecord
      before_save :stamp

      def a_rule
        1
      end
    end
  RUBY

  # Three rules broken, and nothing names it.
  UNCOVERED = <<~RUBY
    class UncoveredRecord < ApplicationRecord
      before_save :stamp
      after_commit :notify

      def a_rule
        1
      end

      def self.another
        2
      end
    end
  RUBY

  # One rule, many times. Nothing tests it either, so only the rule count separates them.
  REPETITIVE = <<~RUBY
    class OneRuleRecord < ApplicationRecord
      def a; end
      def b; end
      def c; end
      def d; end
      def e; end
      def f; end
      def g; end
      def h; end
    end
  RUBY

  def test_a_file_a_test_names_comes_first_even_when_it_breaks_fewer_rules
    units = queue

    assert_equal "app/records/covered_record.rb", units.first.path
    assert units.first.tested
  end

  # Among files nothing tests, six kinds of finding is six problems and sixty of one kind is
  # one problem repeated — so the file breaking more distinct rules comes first, even though
  # the other has far more offences.
  def test_more_distinct_rules_outranks_more_offences
    units = build(
      "app/records/many_rules_record.rb" => UNCOVERED,
      "app/records/one_rule_record.rb" => REPETITIVE,
    )

    assert_equal "app/records/many_rules_record.rb", units.first.path
    assert_operator units.first.offences.length, :<, units.last.offences.length
    assert_operator units.first.cops.length, :>, units.last.cops.length
  end

  def test_a_file_no_test_names_is_offered_but_flagged
    uncovered = queue.find { |unit| unit.path.include?("uncovered") }

    refute_nil uncovered
    refute uncovered.tested, "nothing in test/ names this file"
  end

  # The message is the prompt. A summary would make the unit unactionable on its own.
  def test_each_offence_carries_the_whole_teaching_message
    message = queue.first.offences.first.fetch(:message)

    assert_includes message, "WHY:"
    assert_includes message, "INSTEAD:"
  end

  def test_it_answers_nothing_when_everything_is_clean
    assert_empty build("app/records/clean_record.rb" => "class CleanRecord < ApplicationRecord\nend\n")
  end

  private

  def queue
    @queue ||= build(
      "app/records/covered_record.rb" => COVERED,
      "app/records/uncovered_record.rb" => UNCOVERED,
      "test/records/covered_record_test.rb" => "class CoveredRecordTest\nend\n",
    )
  end

  def build(files)
    Dir.mktmpdir("queue") do |root|
      File.write(File.join(root, ".rubocop.yml"), LAYOUT)
      files.each do |relative, source|
        target = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, source)
      end

      Shipshape::Queue.new(root: root, targets: %w[app]).call(limit: 10)
    end
  end
end
