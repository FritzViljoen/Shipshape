# frozen_string_literal: true

require "test_helper"

# Watched to fail: making `guarded?` answer false reddens the two offence tests; making it answer
# true reddens the anonymous-callee test, which is the shape the law allows; dropping the
# `anonymous_call` check in `on_def` reddens the guarded-caller test, because a normal `call`
# naming a guarded operation is the ordinary case and must stay silent.
class AnonymityIsClosedDownwardTest < Minitest::Test
  include CopRunner

  COP = RuboCop::Cop::Shipshape::AnonymityIsClosedDownward

  LAYOUT = {
    "Shipshape/CallGraph" => {
      "Kinds" => {
        "deed" => ["app/deeds/**/*.rb"],
        "question" => ["app/questions/**/*.rb"],
        "legacy_deed" => ["app/legacy/**/*.rb"],
      },
      "Matrix" => { "deed" => %w[question legacy_deed], "question" => [], "legacy_deed" => [] },
    },
  }.freeze

  TREE = {
    "app/questions/charge_card.rb" => "class ChargeCard < Question\n  def call\n    success(1)\n  end\nend\n",
    "app/questions/find_person_by_email.rb" =>
      "class FindPersonByEmail < Question\n  def anonymous_call\n    Person.new\n  end\nend\n",
    "app/questions/find_secret.rb" => "class FindSecret < Question\n  def call\n    Secret.new\n  end\nend\n",
    "app/legacy/charge_legacy.rb" =>
      "class ChargeLegacy < LegacyDeed\n  def call\n    success(1)\n  end\nend\n",
    # Two classes in one file: the guarded one being called, and a second that is anonymous.
    "app/questions/find_rate.rb" =>
      "class FindRate < Question\n  def call\n    Rate.new\n  end\nend\n\n" \
      "class FindRateCached < Question\n  def anonymous_call\n    Rate.new\n  end\nend\n",
  }.freeze

  CALLER = "app/deeds/log_in.rb"

  def test_an_anonymous_operation_reaching_a_guarded_deed_is_an_offence
    found = check(<<~RUBY)
      class LogIn < Deed
        def anonymous_call
          ChargeCard.call(actor: nil, amount: 1)
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`ChargeCard` is guarded, and this operation is anonymous",
      "**The loophole one level down.** Every permission below this line was satisfied by one declaration at the top of the file."
  end

  def test_the_offence_says_why_anonymity_is_a_claim_about_a_subtree
    message = check(<<~RUBY).first.message
      class LogIn < Deed
        def anonymous_call
          ChargeCard.call(actor: nil)
        end
      end
    RUBY

    assert_includes message, "WHY:"
    assert_includes message, "runs for nobody"
    assert_includes message, "a claim about a whole subtree"
    assert_includes message, "FindPersonByEmail.call(email: @email)"
  end

  def test_a_guarded_question_is_the_same_offence
    assert_equal 1, check(<<~RUBY).length
      class LogIn < Deed
        def anonymous_call
          FindSecret.call
        end
      end
    RUBY
  end

  # Deferring is running, at a different time.
  def test_a_deferred_guarded_call_is_the_same_offence
    assert_equal 1, check(<<~RUBY).length
      class LogIn < Deed
        def anonymous_call
          ChargeCard.call_later(actor: nil)
        end
      end
    RUBY
  end

  # The shape the law allows: anonymity closed downward.
  def test_an_anonymous_operation_reaching_an_anonymous_one_is_the_shape
    assert_empty check(<<~RUBY)
      class LogIn < Deed
        def anonymous_call
          FindPersonByEmail.call(email: @email)
        end
      end
    RUBY
  end

  # **A cop that fails correct code gets disabled.** A guarded operation calling a guarded one
  # is the ordinary case, and aggregation — not this — is what holds it.
  def test_a_guarded_operation_reaching_a_guarded_one_is_not_this_cops_business
    assert_empty check(<<~RUBY)
      class LogIn < Deed
        def call
          ChargeCard.call(actor: @actor)
        end
      end
    RUBY
  end

  # A constant the layout does not govern resolves to no file, so guessing would fail correct
  # code — a gem's class, or a value object.
  def test_a_constant_that_resolves_to_no_file_is_skipped
    assert_empty check(<<~RUBY)
      class LogIn < Deed
        def anonymous_call
          Rails.logger.call
          SomeGem::Client.call(token: @token)
        end
      end
    RUBY
  end

  # **The tree laundering is likeliest in.** A legacy door still checks, and omitting the kind
  # left the cop blind to it in both directions.
  def test_a_guarded_legacy_deed_is_a_step_too
    assert_equal 1, check(<<~RUBY).length
      class LogIn < Deed
        def anonymous_call
          ChargeLegacy.call(actor: nil)
        end
      end
    RUBY
  end

  def test_an_anonymous_call_inside_a_legacy_door_is_inspected
    found = offences(<<~RUBY, cop_class: COP, path: "app/legacy/log_in_legacy.rb", files: TREE, other_cops: LAYOUT)
      class LogInLegacy < LegacyDeed
        def anonymous_call
          ChargeCard.call(actor: nil)
        end
      end
    RUBY

    assert_equal 1, found.length
  end

  def test_a_second_anonymous_class_in_the_file_does_not_excuse_the_callee
    found = check(<<~RUBY)
      class LogIn < Deed
        def anonymous_call
          FindRate.call
        end
      end
    RUBY

    assert_equal 1, found.length
    assert_includes found.first.message, "`FindRate` is guarded",
      "**The callee class's own body, never the file's text.** A second class in the file — or a heredoc — answered for the class actually being called."
  end

  private

  def check(source)
    offences(source, cop_class: COP, path: CALLER, files: TREE, other_cops: LAYOUT)
  end
end
