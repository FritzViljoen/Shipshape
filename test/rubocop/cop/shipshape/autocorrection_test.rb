# frozen_string_literal: true

require "test_helper"

# The deterministic slice of what shipshape finds — 7% of 21,485 offences across seven public
# Rails repositories — is a rewrite no judgement is needed for. This is that rewrite.
class AutocorrectionTest < Minitest::Test
  include CopRunner

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "request_handling" => ["app/controllers/**/*_controller.rb"] },
      "Matrix" => { "request_handling" => [] },
    },
  }.freeze

  CONTROLLER = "app/controllers/things_controller.rb"

  OPERATION = {
    "Shipshape/CallGraph" => {
      "Kinds" => { "write" => ["app/writes/**/*.rb"] },
      "Matrix" => { "write" => [] },
    },
    "Shipshape/OneOperationOneClass" => { "OperationKinds" => ["write"], "PublicMethod" => "call" },
  }.freeze

  def test_a_silent_numeric_cast_is_rewritten_to_a_parser
    assert_corrected "params[:page].to_i", "integer_param!(:page)", RuboCop::Cop::Shipshape::NoSilentCoercion
    assert_corrected "params[:amount].to_f", "decimal_param!(:amount)", RuboCop::Cop::Shipshape::NoSilentCoercion
    assert_corrected "params[:name].to_s", "text_param!(:name)", RuboCop::Cop::Shipshape::NoSilentCoercion
  end

  def test_a_non_literal_key_is_reported_and_left_alone
    assert_unchanged "params[key].to_i", RuboCop::Cop::Shipshape::NoSilentCoercion
  end

  def test_a_primary_key_lookup_is_rewritten
    assert_corrected "ThingRecord.find(params[:id])", "ThingRecord.find(integer_param!(:id))",
                     RuboCop::Cop::Shipshape::NoUnparsedLookup
  end

  # Over lobsters `short_id` is base 36, so rewriting to `integer_param!` would have broken
  # every one of those lookups. A `_id` suffix says nothing about the type.
  def test_a_suffixed_key_is_reported_and_left_alone
    assert_unchanged "ThingRecord.where(short_id: params[:story_id])",
                     RuboCop::Cop::Shipshape::NoUnparsedLookup
    assert_unchanged "ThingRecord.find_by(short_id: params[:hat_id])",
                     RuboCop::Cop::Shipshape::NoUnparsedLookup
  end

  def test_a_value_that_is_not_an_id_is_reported_and_left_alone
    assert_unchanged "ThingRecord.where(state: params[:state])", RuboCop::Cop::Shipshape::NoUnparsedLookup
  end

  # The vulnerability this cop nearly shipped: rewriting a session read moves the value to the
  # query string, turning an OAuth state check into a comparison of a parameter with itself.
  def test_only_params_is_ever_rewritten
    %w[session cookies env request].each do |source|
      assert_unchanged "#{source}[:token].to_s", RuboCop::Cop::Shipshape::NoSilentCoercion
    end
  end

  def test_a_mixed_comparison_corrects_only_the_parameter_half
    corrected = correct(action("params[:state].to_s != session[:state].to_s"),
                        RuboCop::Cop::Shipshape::NoSilentCoercion)

    assert_includes corrected, "text_param!(:state) != session[:state].to_s"
  end

  def test_a_nested_or_defaulted_read_is_left_alone
    assert_unchanged "params[:filter][:page].to_i", RuboCop::Cop::Shipshape::NoSilentCoercion
    assert_unchanged 'params.fetch(:page, "7").to_i', RuboCop::Cop::Shipshape::NoSilentCoercion
  end

  # `Integer(params[:code], 16)` carries a base the rewrite would drop.
  def test_a_conversion_with_a_base_is_left_alone
    assert_unchanged "Integer(params[:code], 16)", RuboCop::Cop::Shipshape::NoInlineParamParse
  end

  def test_a_file_that_is_not_a_door_is_reported_and_left_alone
    source = "class Report\n  def call\n    params[:page].to_i\n  end\nend\n"
    path = "app/reads/report.rb"
    layout = { "Shipshape/CallGraph" => { "Kinds" => { "read" => ["app/reads/**/*.rb"] },
                                          "Matrix" => { "read" => [] } } }

    refute_empty offences(source, cop_class: RuboCop::Cop::Shipshape::NoSilentCoercion,
                                  path: path, other_cops: layout)
    assert_equal source, correct(source, RuboCop::Cop::Shipshape::NoSilentCoercion, path: path, layout: layout),
      "`integer_param!` lives in TypedParams, wired into ApplicationController and nowhere else. Correcting a plain object that happens to expose `params` emits a call to a method that does not exist there — 203 of these went into discourse before this guard."
  end

  def test_a_raising_conversion_is_rewritten
    assert_corrected "Integer(params[:id])", "integer_param!(:id)", RuboCop::Cop::Shipshape::NoInlineParamParse
    assert_corrected "BigDecimal(params[:amount])", "decimal_param!(:amount)",
                     RuboCop::Cop::Shipshape::NoInlineParamParse
  end

  # `date_param!` takes a zone, and inventing one is the cop writing the defect it forbids.
  def test_a_date_parse_is_reported_and_left_alone
    assert_unchanged "Date.parse(params[:on])", RuboCop::Cop::Shipshape::NoInlineParamParse
  end

  # `call` stays public: `Shipshape/OnlyTheDoorIsCalled` refuses `Settle.new` at the call site.
  def test_a_public_operation_is_corrected_by_scaffolding_private
    source = <<~RUBY
      class Settle
        def initialize(amount:)
          @amount = amount
        end

        def call
          helper
        end

        def helper
          1
        end
      end
    RUBY

    corrected = correct(source, RuboCop::Cop::Shipshape::OneOperationOneClass,
                        path: "app/writes/settle.rb", layout: OPERATION)

    assert_includes corrected, "  def call\n    helper\n  end\n\n  private\n\n  def helper"
    assert_equal 1, corrected.scan(/^\s*private$/).length, "one private, not one per method"
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

  def correct(source, cop_class, path: CONTROLLER, layout: LAYOUT)
    Dir.mktmpdir("correct") do |root|
      relative = path
      path = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, source)

      # Merge, not replace: overwriting the cop's entry dropped `OperationKinds` silently.
      own = { "Enabled" => true }.merge(layout.fetch(cop_class.cop_name, {}))
      config = RuboCop::Config.new(layout.merge(cop_class.cop_name => own),
                                   File.join(root, ".rubocop.yml"))
      team = RuboCop::Cop::Team.new([cop_class.new(config, RuboCop::Options.new.parse(["-A"]).first)],
                                    config, raise_error: true, autocorrect: true)
      processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, path)
      report = team.investigate(processed)

      report.correctors.compact.first&.rewrite || source
    end
  end
end
