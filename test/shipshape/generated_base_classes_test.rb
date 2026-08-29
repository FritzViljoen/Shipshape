# frozen_string_literal: true

require "test_helper"
require "shipshape/install"

# The installer's own test proves the files are written and compile. This one loads them
# and exercises the contracts, because "it parses" is not "it holds" — a base class that
# accepted any return value would compile perfectly and enforce nothing.
#
# ActiveRecord is not here, so the two templates that open a transaction are given a stand
# in that yields. That is honest: what is under test is the Result contract, not Rails.
#
# Installed with `auth: true`, because these exercise the authorisation contracts. The
# opt-in itself — and what the default writes — is `install_auth_test.rb`.
class GeneratedBaseClassesTest < Minitest::Test
  def self.load_generated_once
    root = Dir.mktmpdir("shipshape-generated")
    Shipshape::Install.new(root: root, auth: true).call

    stub_active_record
    Shipshape::Install::FILES.each { |name| require File.join(root, "app/shipshape/#{name}.rb") }
  end

  def self.stub_active_record
    return if defined?(::ActiveRecord)

    base = Class.new do
      def self.transaction
        yield
      end
    end
    Object.const_set(:ActiveRecord, Module.new)
    ::ActiveRecord.const_set(:Base, base)
  end

  load_generated_once

  # Says yes to everything except the one permission the refusal tests name.
  Anyone = Struct.new(:refuses) do
    def may?(permission)
      !Array(refuses).include?(permission)
    end
  end

  ANYONE = Anyone.new([]).freeze

  class Charge < Command
    def initialize(actor:, amount:)
      @actor = actor
      @amount = typed(amount, Integer)
    end

    def call
      @amount.positive? ? success(@amount) : failure(:not_positive)
    end
  end

  class Misbehaving < Command
    def initialize(actor:)
      @actor = actor
    end

    def call
      "a bare string"
    end
  end

  class Place < Shape
    def initialize(code:)
      @code = typed(code, String)
    end
  end

  class ListPlaces < Query
    def initialize(actor:)
      @actor = actor
    end

    def call
      [Place.new(code: "ZA")]
    end
  end

  class LeakyQuery < Query
    def initialize(actor:)
      @actor = actor
    end

    def call
      [{ code: "ZA" }]
    end
  end

  def test_a_command_answers_with_a_result
    result = Charge.call(actor: ANYONE, amount: 5)

    assert_predicate result, :success?
    assert_equal 5, result.value
    assert_nil result.error
  end

  def test_an_expected_failure_comes_back_as_a_value
    result = Charge.call(actor: ANYONE, amount: 0)

    refute_predicate result, :success?
    assert_equal :not_positive, result.error
  end

  # The contract is enforced at the class method, so a subclass cannot teach its callers a
  # second shape.
  def test_a_command_that_answers_with_anything_else_stops_the_run
    error = assert_raises(TypeError) { Misbehaving.call(actor: ANYONE) }

    assert_includes error.message, "must answer with a Result"
  end

  def test_arguments_are_asserted_at_construction
    assert_raises(ArgumentError) { Charge.call(actor: ANYONE, amount: "5") }
  end

  def test_a_query_answers_with_shapes_and_no_envelope
    answer = ListPlaces.call(actor: ANYONE)

    assert_equal [Place.new(code: "ZA")], answer
  end

  # Whatever the old code returned, the door decides the shape. A query leaking hashes is
  # the leak this check exists to stop.
  def test_a_query_that_answers_with_anything_else_stops_the_run
    error = assert_raises(TypeError) { LeakyQuery.call(actor: ANYONE) }

    assert_includes error.message, "must answer with shapes"
  end

  # The permission IS the class name — no transform, because every transform is lossy and
  # a lossy one collides. `FooBar` and `Foo::Bar` both underscored to `:foo_bar`.
  def test_a_permission_is_the_class_name
    assert_equal :"GeneratedBaseClassesTest::Charge", Charge.permission
  end

  def test_two_classes_that_would_underscore_alike_keep_distinct_permissions
    flat = Class.new(Command) do
      def self.name
        "FooBar"
      end
    end
    nested = Class.new(Command) do
      def self.name
        "Foo::Bar"
      end
    end

    refute_equal flat.permission, nested.permission
  end

  # The whole point: a new operation is denied until someone grants it deliberately.
  def test_a_command_refused_answers_with_a_value
    refuser = Anyone.new([Charge.permission])

    result = Charge.call(actor: refuser, amount: 5)

    refute_predicate result, :success?
    assert_equal :forbidden, result.error
  end

  # A query has no envelope, so refusal raises like every other query failure.
  def test_a_refused_query_raises
    refuser = Anyone.new([ListPlaces.permission])

    assert_raises(Permission::Refused) { ListPlaces.call(actor: refuser) }
  end

  # A refusal costs no lock: the check runs before the transaction opens.
  def test_a_refused_command_never_opens_a_transaction
    opened = false
    ::ActiveRecord::Base.define_singleton_method(:transaction) { |&block| opened = true; block.call }

    Charge.call(actor: Anyone.new([Charge.permission]), amount: 5)

    refute opened
  ensure
    ::ActiveRecord::Base.define_singleton_method(:transaction) { |&block| block.call }
  end

  def test_a_workflow_answers_the_permissions_of_its_steps
    flow = Class.new(Workflow) do
      const_set(:STEPS, [Charge].freeze)
      def self.name
        "SettleMonth"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:done)
      end
    end

    assert_equal [Charge.permission], flow.permissions
  end

  def test_a_workflow_refuses_before_a_single_step_runs
    ran = false
    flow = Class.new(Workflow) do
      const_set(:STEPS, [Charge].freeze)
      def self.name
        "SettleMonth"
      end

      define_method(:initialize) { |actor:| @actor = actor }
      define_method(:call) { ran = true; success(:done) }
    end

    result = flow.call(actor: Anyone.new([Charge.permission]))

    refute_predicate result, :success?
    assert_equal :forbidden, result.error
    refute ran, "the workflow body ran despite a refused step"
  end

  # Publicness is a property of the class — which method it implements — never of the
  # caller. There is no `public_call` a caller could reach for on a guarded operation.
  class LogIn < Command
    def initialize(email:)
      @email = typed(email, String)
    end

    def anonymous_call
      success(@email)
    end
  end

  def test_an_operation_implementing_anonymous_call_runs_unchecked
    result = LogIn.call(email: "a@b.c")

    assert_predicate result, :success?
    assert_equal "a@b.c", result.value
  end

  def test_an_anonymous_operation_needs_no_actor_at_all
    refuses_everything = Anyone.new([LogIn.permission])

    assert_predicate LogIn.call(actor: refuses_everything, email: "a@b.c"), :success?
  end

  # A nil actor taken to mean "public" would be the fail-open the whole model prevents.
  def test_a_guarded_operation_with_no_actor_raises
    error = assert_raises(ArgumentError) { Charge.call(amount: 5) }

    assert_includes error.message, "requires an actor"
  end

  # These wrap the highest-risk code in a consuming app and had no check at all.
  def test_a_legacy_door_is_guarded_like_everything_else
    wipe = Class.new(LegacyCommand) do
      def self.name
        "WipeEverything"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:wiped)
      end
    end

    assert_raises(ArgumentError) { wipe.call }
    refute_predicate wipe.call(actor: Anyone.new([wipe.permission])), :success?
  end

  # An inherited empty STEPS meant a workflow that forgot to declare one refused nobody.
  def test_a_workflow_that_forgets_steps_raises_rather_than_running
    forgetful = Class.new(Workflow) do
      def self.name
        "Forgetful"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:done)
      end
    end

    error = assert_raises(NotImplementedError) { forgetful.call(actor: ANYONE) }

    assert_includes error.message, "must declare STEPS"
  end

  # An anonymous step is never granted — that is what anonymous means — so aggregating its
  # name demanded a grant nobody could hold and made the whole workflow permanently
  # forbidden.
  def test_an_anonymous_step_contributes_no_permission
    flow = Class.new(Workflow) do
      const_set(:STEPS, [LogIn, Charge].freeze)
      def self.name
        "Onboard"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:onboarded)
      end
    end

    assert_equal [Charge.permission], flow.permissions
    # Refuses only `:LogIn` — the permission an anonymous step must never contribute.
    assert_predicate flow.call(actor: Anyone.new([LogIn.permission])), :success?
  end

  # A signup sequence runs before anyone is identified, and says so the same way an
  # operation does.
  def test_a_workflow_may_be_anonymous
    flow = Class.new(Workflow) do
      const_set(:STEPS, [LogIn].freeze)
      def self.name
        "SignUp"
      end

      def initialize(email:)
        @email = email
      end

      def anonymous_call
        success(@email)
      end
    end

    result = flow.call(email: "a@b.c")

    assert_predicate result, :success?
    assert_equal "a@b.c", result.value
  end

  # The guarded path still demands one, so anonymity stays a property of the class.
  def test_a_guarded_workflow_still_requires_an_actor
    flow = Class.new(Workflow) do
      const_set(:STEPS, [Charge].freeze)
      def self.name
        "SettleMonth"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:done)
      end
    end

    assert_raises(ArgumentError) { flow.call }
  end

  # The method a view reaches for. Inherited from Permission it asked the workflow's OWN
  # name, which is never granted, so it answered false for an actor who may run every step
  # — the button hidden from everybody.
  def test_a_workflow_answers_whether_the_actor_may_run_it
    flow = Class.new(Workflow) do
      const_set(:STEPS, [LogIn, Charge].freeze)
      def self.name
        "Onboard"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:done)
      end
    end

    assert flow.permits?(Anyone.new([LogIn.permission])), "an anonymous step must not gate the view"
    refute flow.permits?(Anyone.new([Charge.permission]))
  end

  def test_the_view_predicate_and_the_refusal_are_one_question
    flow = Class.new(Workflow) do
      const_set(:STEPS, [Charge].freeze)
      def self.name
        "SettleMonth"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        success(:done)
      end
    end

    refuser = Anyone.new([Charge.permission])

    refute flow.permits?(refuser)
    refute_predicate flow.call(actor: refuser), :success?
  end

  def test_an_empty_answer_is_an_answer
    empty = Class.new(Query) do
      def self.name
        "EmptyQuery"
      end

      def initialize(actor:)
        @actor = actor
      end

      def call
        []
      end
    end

    assert_empty empty.call(actor: ANYONE)
  end

  # Value semantics without a macro: two shapes of a class holding the same values are
  # the same shape, so they compare, deduplicate and assert equal.
  def test_shapes_compare_by_value
    assert_equal Place.new(code: "ZA"), Place.new(code: "ZA")
    refute_equal Place.new(code: "ZA"), Place.new(code: "GB")
    assert_equal 1, [Place.new(code: "ZA"), Place.new(code: "ZA")].uniq.length
  end

  def test_an_error_code_is_a_name_not_a_sentence
    assert_raises(ArgumentError) { Result.failure("something went wrong") }
  end

  def test_boolean_is_a_name_and_reopens_nothing
    refute_includes true.class.ancestors, Boolean
    assert_equal "Boolean", Boolean.to_s
  end
end
