# frozen_string_literal: true

require "test_helper"

# The deterministic slice of what shipshape finds — 7% of 21,485 offences across seven public
# Rails repositories — is a rewrite no judgement is needed for. This is that rewrite.
#
# **Every correction here is `SafeAutoCorrect: false`.** `"banana".to_i` is 0 today and a
# bounce afterwards; that is the rule, and it is not behaviour-preserving. Applying it
# silently under `-a` would be the same sin these cops are named for.
#
# Watched to fail, as `a-guard-states-its-limit` requires:
#
# - Making `correction_for` answer nil in each cop reddens that cop's rewrite test.
# - Dropping the literal-key guard reddens the non-literal tests.
# - Dropping the id check in NoUnparsedLookup reddens the `where(state:)` test — the one
#   that stops a silent wrong answer becoming a confident one.
class AutocorrectionTest < Minitest::Test
  include CopRunner

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "request_handling" => ["app/controllers/**/*_controller.rb"] },
      "Matrix" => { "request_handling" => [] },
    },
  }.freeze

  CONTROLLER = "app/controllers/things_controller.rb"

  def test_a_silent_numeric_cast_is_rewritten_to_a_parser
    assert_corrected "params[:page].to_i", "integer_param!(:page)", RuboCop::Cop::Shipshape::NoSilentCoercion
    assert_corrected "params[:amount].to_f", "decimal_param!(:amount)", RuboCop::Cop::Shipshape::NoSilentCoercion
    assert_corrected "params[:name].to_s", "text_param!(:name)", RuboCop::Cop::Shipshape::NoSilentCoercion
  end

  # `params[key]` names a parameter the source does not contain.
  def test_a_non_literal_key_is_reported_and_left_alone
    assert_unchanged "params[key].to_i", RuboCop::Cop::Shipshape::NoSilentCoercion
  end

  # The primary key, positionally. Rails makes it an integer.
  def test_a_primary_key_lookup_is_rewritten
    assert_corrected "ThingRecord.find(params[:id])", "ThingRecord.find(integer_param!(:id))",
                     RuboCop::Cop::Shipshape::NoUnparsedLookup
  end

  # Found by running the correction over lobsters, where `short_id` is base 36: rewriting
  # this to `integer_param!` would have broken every one of those lookups. A `_id` suffix
  # says nothing about the type — only the column does, and it is not in the source.
  def test_a_suffixed_key_is_reported_and_left_alone
    assert_unchanged "ThingRecord.where(short_id: params[:story_id])",
                     RuboCop::Cop::Shipshape::NoUnparsedLookup
    assert_unchanged "ThingRecord.find_by(short_id: params[:hat_id])",
                     RuboCop::Cop::Shipshape::NoUnparsedLookup
  end

  def test_a_value_that_is_not_an_id_is_reported_and_left_alone
    assert_unchanged "ThingRecord.where(state: params[:state])", RuboCop::Cop::Shipshape::NoUnparsedLookup
  end

  def test_a_raising_conversion_is_rewritten
    assert_corrected "Integer(params[:id])", "integer_param!(:id)", RuboCop::Cop::Shipshape::NoInlineParamParse
    assert_corrected "BigDecimal(params[:amount])", "decimal_param!(:amount)",
                     RuboCop::Cop::Shipshape::NoInlineParamParse
  end

  # `date_param!` takes a zone, and which zone is a decision the source does not contain.
  # `a-time-names-its-zone` says a zone nobody stated is a fact nobody declared — inventing
  # one here would be the cop writing the defect it forbids.
  def test_a_date_parse_is_reported_and_left_alone
    assert_unchanged "Date.parse(params[:on])", RuboCop::Cop::Shipshape::NoInlineParamParse
  end

  private

  def action(body)
    "class ThingsController\n  def show\n    #{body}\n  end\nend\n"
  end

  def assert_corrected(before, after, cop_class)
    corrected = correct(action(before), cop_class)

    assert_includes corrected, after
    refute_includes corrected, before
  end

  def assert_unchanged(before, cop_class)
    source = action(before)
    found = offences(source, cop_class: cop_class, path: CONTROLLER, other_cops: LAYOUT)

    refute_empty found, "expected #{before} to be reported"
    assert_equal source, correct(source, cop_class), "#{before} must be reported, not rewritten"
  end

  def correct(source, cop_class)
    Dir.mktmpdir("correct") do |root|
      path = File.join(root, CONTROLLER)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, source)

      config = RuboCop::Config.new(
        LAYOUT.merge(cop_class.cop_name => { "Enabled" => true }),
        File.join(root, ".rubocop.yml"),
      )
      team = RuboCop::Cop::Team.new([cop_class.new(config, RuboCop::Options.new.parse(["-A"]).first)],
                                    config, raise_error: true, autocorrect: true)
      processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, path)
      report = team.investigate(processed)

      report.correctors.compact.first&.rewrite || source
    end
  end
end
