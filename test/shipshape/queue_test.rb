# frozen_string_literal: true

require "test_helper"
require "shipshape/queue"

# Watched to fail: removing the `tested` term from `ranked` reddens the covered-first test;
# removing the `-unit.cops.length` term reddens the distinct-rules test; making `named_in_a_test?`
# answer true reddens the coverage tests; emptying `TOO_COMMON` reddens the vocabulary test;
# dropping the class check reddens the orphan test.
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

      def settlement_total
        1
      end
    end
  RUBY

  # Three rules broken, and nothing names it.
  UNCOVERED = <<~RUBY
    class UncoveredRecord < ApplicationRecord
      before_save :stamp
      after_commit :notify

      def unwitnessed_rule
        1
      end

      def self.unwitnessed_scope
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

  def test_the_best_covered_file_comes_first
    units = queue

    assert_equal "app/records/covered_record.rb", units.first.path
    assert_empty units.first.unnamed
    assert_equal 1, units.first.methods,
      "**The ratio, not a boolean.** A file with one covered method of eighty used to outrank one with all of its methods covered, which is the wrong way round: what matters is how much of the file can be moved before the work stops being verifiable."
  end

  def test_it_names_the_methods_no_test_mentions
    uncovered = queue.find { |unit| unit.path.include?("uncovered") }

    assert_equal %w[unwitnessed_rule unwitnessed_scope], uncovered.unnamed
    assert_equal 0, uncovered.covered,
      "A file-level answer says nothing about the method you are about to move."
  end

  def test_more_distinct_rules_outranks_more_offences
    units = build(
      "app/records/many_rules_record.rb" => UNCOVERED,
      "app/records/one_rule_record.rb" => REPETITIVE,
    )

    assert_equal "app/records/many_rules_record.rb", units.first.path,
      "Among files nothing tests, six kinds of finding is six problems and sixty of one kind is one problem repeated — so the file breaking more distinct rules comes first, even though the other has far more offences."
    assert_operator units.first.offences.length, :<, units.last.offences.length
    assert_operator units.first.cops.length, :>, units.last.cops.length
  end

  def test_a_file_no_test_names_is_offered_but_flagged
    uncovered = queue.find { |unit| unit.path.include?("uncovered") }

    refute_nil uncovered
    refute uncovered.tested, "no method of this file is named in any test"
  end

  def test_each_offence_carries_the_whole_teaching_message
    message = queue.first.offences.first.fetch(:message)

    assert_includes message, "WHY:"
    assert_includes message, "INSTEAD:",
      "The message is the prompt. A summary would make the unit unactionable on its own."
  end

  def test_it_answers_nothing_when_everything_is_clean
    assert_empty build("app/records/clean_record.rb" => "class CleanRecord < ApplicationRecord\nend\n")
  end

  def test_ruby_s_own_vocabulary_is_not_evidence_of_coverage
    units = build(
      "app/records/common_record.rb" =>
        "class CommonRecord < ApplicationRecord\n  before_save :x\n\n  def call\n    1\n  end\n\n" \
        "  def name\n    2\n  end\nend\n",
      "test/records/unrelated_test.rb" =>
        "class UnrelatedTest\n  def test_it\n    thing.call\n    thing.name\n  end\nend\n",
    )

    assert_equal 0, units.first.methods, "call and name are not this file's evidence"
    assert_equal 0, units.first.covered,
      "**Ruby's own vocabulary would mark everything covered.** `call`, `name`, `each` appear in every test file whether or not this class is tested, so matching them answers yes for a file nothing exercises — the flattering answer, and the dangerous one here."
  end

  # A method name is only evidence where the class is named too. Over lobsters this ranked an
  # untested controller safest to start here, because its methods are `show` and `expire`.
  def test_a_method_name_is_not_coverage_when_nothing_names_the_class
    units = build(
      "app/records/orphan_record.rb" =>
        "class OrphanRecord < ApplicationRecord\n  before_save :x\n\n  def expire\n    1\n  end\nend\n",
      "test/records/unrelated_test.rb" =>
        "class UnrelatedTest\n  def test_it\n    session.expire\n  end\nend\n",
    )

    assert_equal %w[expire], units.first.unnamed,
                 "`expire` is an ordinary word, and no test names OrphanRecord"
    refute units.first.tested,
           "a file nothing names must not be offered as the safe place to start"
  end

  private

  def queue
    @queue ||= build(
      "app/records/covered_record.rb" => COVERED,
      "app/records/uncovered_record.rb" => UNCOVERED,
      "test/records/covered_record_test.rb" =>
        "class CoveredRecordTest\n  def test_it\n    record.settlement_total\n  end\nend\n",
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
