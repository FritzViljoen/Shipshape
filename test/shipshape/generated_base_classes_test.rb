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
    Shipshape::Install.new(root: root, auth: true, view_components: true).call

    stub_active_record
    stub_view_component
    stub_active_job
    stub_descendants
    Shipshape::Install::FILES.each { |name| require File.join(root, "app/shipshape/#{name}.rb") }
  end

  # The generated component base inherits from the gem. Standing it in is what lets this
  # suite prove the refusal without the gem — the refusal is ours, the superclass is not.
  def self.stub_view_component
    return if defined?(::ViewComponent)

    Object.const_set(:ViewComponent, Module.new)
    ::ViewComponent.const_set(:Base, Class.new)
  end

  # ActiveJob is not loaded in this suite. The stand-in records enqueues and can run `perform`,
  # which is what lets the per-operation retry limit be exercised rather than described.
  def self.stub_active_job
    return if defined?(::ActiveJob)

    base = Class.new do
      class << self
        attr_accessor :enqueued

        def set(**options)
          @options = options
          self
        end

        def perform_later(**arguments)
          (self.enqueued ||= []) << arguments
          new
        end
      end

      attr_accessor :executions

      def initialize
        @executions = 1
      end

      def retry_job(**)
        @executions += 1
        self
      end
    end

    Object.const_set(:ActiveJob, Module.new)
    ::ActiveJob.const_set(:Base, base)

  end

  def self.stub_descendants
    Class.instance_eval do
      define_method(:descendants) do
        ObjectSpace.each_object(Class).select { |klass| klass < self }
      end
    end
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
    # `Shape` refuses to hold either, and asks the constant rather than the name — so the
    # stand-in has to carry both or the refusal is never exercised.
    ::ActiveRecord.const_set(:Relation, Class.new)
  end

  load_generated_once

  # Says yes to everything except the one permission the refusal tests name.
  Anyone = Struct.new(:refuses) do
    def may?(permission)
      !Array(refuses).include?(permission)
    end
  end

  ANYONE = Anyone.new([]).freeze

  # **An actor a deferred job can find again.** `Anyone` has no `id`, which is legitimate —
  # `permits?` needs only `may?` — and is precisely the shape `call_later` used to drop.
  Named = Struct.new(:id) do
    def may?(_permission)
      true
    end
  end

  NAMED = Named.new(7).freeze

  # Pointing the sink somewhere is what an application does on install; a test suite is no
  # different. The default is deliberately noisy — never silent — which is right in production
  # and wrong in a test run.
  AuditLog.sink = ->(_entry) {}

  class Charge < Command
    def initialize(amount:)
      @amount = typed(amount, Integer)
    end

    def call
      @amount.positive? ? success(@amount) : failure(:not_positive)
    end
  end

  class Misbehaving < Command
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
    def call
      [Place.new(code: "ZA")]
    end
  end

  class LeakyQuery < Query
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

      def call
        success(:done)
      end
    end

    refuser = Anyone.new([Charge.permission])

    refute flow.permits?(refuser)
    refute_predicate flow.call(actor: refuser), :success?
  end

  # The catalogue is read off the classes, so it cannot fall behind them. An operation in no
  # capability is unreachable — fail-closed, correct, and invisible — and this is the half
  # shipshape can supply: the other half is the application's own table.
  def test_the_catalogue_is_every_grantable_permission
    catalogue = Permission.catalogue(Command, Query)

    assert_includes catalogue, Charge.permission
    assert_includes catalogue, ListPlaces.permission
  end

  # Never granted, so demanding a capability contain one would fail every check for ever.
  def test_the_catalogue_leaves_out_anonymous_operations
    refute_includes Permission.catalogue(Command), LogIn.permission
  end

  # A door of its own, so the catalogue under test is this file's classes and not every
  # subclass any other test in the process happened to create.
  class CataloguedFlow < Workflow; end

  class SettleMonthFlow < CataloguedFlow
    STEPS = [Charge].freeze
  end

  def test_a_workflow_contributes_its_steps_not_its_own_name
    catalogue = Permission.catalogue(CataloguedFlow)

    assert_includes catalogue, Charge.permission
    refute_includes catalogue, SettleMonthFlow.permission
  end

  # Not a wart: that workflow would otherwise refuse nothing at its first real call, in
  # production. Walking the catalogue at boot is the cheapest place to find it.
  def test_the_catalogue_raises_on_a_workflow_that_declares_no_steps
    error = assert_raises(NotImplementedError) { Permission.catalogue(Workflow) }

    # Either broken workflow in this file may be met first, depending on run order: one
    # declares no STEPS, the other declares an empty one. Both are the same defect.
    assert_match(/STEPS|no steps/, error.message)
  end

  # **The fail-open the guard did not cover.** `const_defined?` catches a missing STEPS; an
  # explicitly empty one yielded `permissions == []`, and `[].all?` is true, so the workflow
  # ran for an actor holding no grants at all.
  def test_a_workflow_declaring_an_empty_steps_raises
    empty = Class.new(Workflow) do
      const_set(:STEPS, [].freeze)
      def self.name
        "ChargeEveryone"
      end
    end

    error = assert_raises(NotImplementedError) { empty.call(actor: ANYONE) }

    assert_includes error.message, "declares no steps"
  end

  # **Publicness is declared by the class that is public.** `method_defined?` walked the
  # ancestor chain, so a subclass of an anonymous command inherited its exemption and ran
  # with no actor and no check.
  def test_anonymity_is_not_inherited_from_a_parent
    child = Class.new(LogIn) do
      def self.name
        "AdminUpload"
      end
    end

    refute_predicate child, :anonymous?
    assert_raises(ArgumentError) { child.call(email: "a@b.c") }
  end

  # Same hole through a concern: one module made every command that included it public.
  def test_anonymity_is_not_granted_by_an_included_module
    bootstrappable = Module.new do
      def anonymous_call
        Result.success(:public)
      end
    end
    command = Class.new(Command) do
      include bootstrappable
      def self.name
        "DeleteAllTenants"
      end
    end

    refute_predicate command, :anonymous?
    assert_raises(ArgumentError) { command.call }
  end

  # **The actor is the base class's, not the signature's.** Forcing `actor:` into every
  # initializer would put a keyword in fifty constructors so that three could read it.
  def test_an_operation_need_not_declare_the_actor
    silent = Class.new(Command) do
      def self.name
        "SilentAboutActors"
      end

      def initialize(amount:)
        @amount = amount
      end

      private

      def call
        success(@amount)
      end
    end

    assert_predicate silent.call(actor: ANYONE, amount: 7), :success?
  end

  # And an operation that wants it reads it, without ever declaring it.
  def test_an_operation_may_read_the_actor_it_never_asked_for
    reader = Class.new(Command) do
      def self.name
        "ReadsTheActor"
      end

      def initialize; end

      private

      def call
        success(actor)
      end
    end

    assert_equal ANYONE, reader.call(actor: ANYONE).value
  end

  def test_an_empty_answer_is_an_answer
    empty = Class.new(Query) do
      def self.name
        "EmptyQuery"
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

  # A code alone cannot render a form, which is the commonest expected failure there is.
  def test_a_failure_may_carry_what_was_wrong
    result = Result.failure(:invalid, Place.new(code: "ZA"))

    refute_predicate result, :success?
    assert_equal :invalid, result.error
    assert_equal Place.new(code: "ZA"), result.value
  end

  def test_a_failure_still_carries_nothing_by_default
    assert_nil Result.failure(:invalid).value
  end

  # The payload obeys the rule everything a shape holds obeys.
  def test_a_failure_may_not_carry_a_record
    assert_raises(TypeError) { Result.failure(:invalid, RECORD.new) }
  end

  # **Every door reports to one place**, which is the uniform shape paying for itself. The
  # refusal is the entry that matters most: a caller told no is what somebody comes looking
  # for, and it is the one nobody has.
  class Bounces < Command
    def initialize; end

    def call
      failure(:nope)
    end
  end

  def audited
    entries = []
    previous = AuditLog.sink
    AuditLog.sink = ->(entry) { entries << entry }
    yield
    entries
  ensure
    AuditLog.sink = previous
  end

  def test_a_successful_command_is_recorded
    entries = audited { Charge.call(actor: ANYONE, amount: 5) }

    assert_equal 1, entries.length
    assert_equal :succeeded, entries.first.outcome
    assert_nil entries.first.error
  end

  def test_a_failed_command_is_recorded_with_its_code
    entries = audited { Bounces.call(actor: ANYONE) }

    assert_equal :failed, entries.first.outcome
    assert_equal :nope, entries.first.error
  end

  # The entry nobody has when they need it.
  def test_a_refusal_is_recorded
    entries = audited { Charge.call(actor: Anyone.new([Charge.permission]), amount: 5) }

    assert_equal :refused, entries.first.outcome
    assert_equal :forbidden, entries.first.error
  end

  # **Arguments are deliberately absent.** An audit log is the classic place personal data
  # leaks: written on every call, kept longer than the rows it describes, and forgotten by
  # every erasure request ever written.
  def test_no_arguments_are_recorded
    entries = audited { Charge.call(actor: ANYONE, amount: 5) }

    refute_respond_to entries.first, :arguments
    assert_equal %i[@actor_id @error @operation @outcome].sort,
                 entries.first.instance_variables.sort
  end

  # An entry is a shape, so it obeys every rule a shape obeys.
  def test_an_entry_is_a_value
    assert_equal AuditLog::Entry.new(operation: "X", outcome: :succeeded),
                 AuditLog::Entry.new(operation: "X", outcome: :succeeded)
  end

  # **Deferral, at the one grain where it is safe:** one command, one transaction, one job.
  class Slow < Command
    QUEUE = :payments
    ATTEMPTS = 2

    def initialize(amount:)
      @amount = typed(amount, Integer)
    end

    def call
      success(@amount)
    end
  end

  def enqueued
    OperationJob.enqueued = []
    yield
    OperationJob.enqueued
  end

  def test_call_later_enqueues_the_operation_by_name
    jobs = enqueued { Slow.call_later(actor: NAMED, amount: 5) }

    assert_equal 1, jobs.length
    assert_equal "GeneratedBaseClassesTest::Slow", jobs.first[:operation]
    assert_equal({ amount: 5 }, jobs.first[:arguments])
  end

  # The Result describes the enqueue, never the work.
  def test_call_later_answers_that_it_was_accepted
    result = nil
    enqueued { result = Slow.call_later(actor: NAMED, amount: 5) }

    assert_predicate result, :success?
    assert_equal :enqueued, result.value
  end

  # Checked here so the caller learns immediately, and again when the job runs.
  def test_call_later_refuses_before_enqueuing
    jobs = nil
    result = nil
    jobs = enqueued { result = Slow.call_later(actor: Anyone.new([Slow.permission]), amount: 5) }

    assert_equal :forbidden, result.error
    assert_empty jobs
  end

  def test_the_queue_is_declared_on_the_operation
    assert_equal :payments, Slow.send(:queue_name)
    assert_equal :default, Charge.send(:queue_name)
  end

  # **Per-operation, from one job class.** `retry_on` would capture one limit for every
  # command; reading `RETRIES` at the moment the decision is made is what makes it per
  # operation.
  def test_the_retry_limit_is_read_from_the_operation
    job = OperationJob.new

    assert_equal 2, job.send(:attempts_for, "GeneratedBaseClassesTest::Slow")
    assert_equal OperationJob::DEFAULT_ATTEMPTS, job.send(:attempts_for, "GeneratedBaseClassesTest::Charge")
  end

  # **An id is not an Integer.** A UUID primary key is an ordinary Rails choice, and this
  # raised after the transaction had committed — telling the caller the command failed when
  # it had succeeded. The suite missed it because its own actor has no `id` at all.
  Uuid = Struct.new(:id) do
    def may?(_permission)
      true
    end
  end

  def test_an_actor_with_a_uuid_is_recorded
    entries = audited { Charge.call(actor: Uuid.new("6f1c8a2e-0b3d"), amount: 5) }

    assert_equal "6f1c8a2e-0b3d", entries.first.actor_id
  end

  def test_an_integer_id_is_recorded_as_text
    entries = audited { Charge.call(actor: Uuid.new(7), amount: 5) }

    assert_equal "7", entries.first.actor_id
  end

  # **A broken sink does not fail the command.** The write has committed by the time the log
  # runs, so raising here would have the audit trail deciding the outcome of the thing it is
  # auditing.
  def test_a_sink_that_raises_does_not_fail_a_committed_command
    previous = AuditLog.sink
    AuditLog.sink = ->(_entry) { raise "sink down" }

    result = Charge.call(actor: ANYONE, amount: 5)

    assert_predicate result, :success?
  ensure
    AuditLog.sink = previous
  end

  # **A shape is a hash with a declared shape.** The documented audit sink writes `entry.to_h`
  # to a table; that method is on `Shape`, so every shape has it and the round trip is
  # `new(**shape.to_h)` with nothing in between — no packer and no serialiser.
  def test_a_shape_is_its_hash
    entry = AuditLog::Entry.new(operation: "X", outcome: :succeeded, actor_id: "1", error: nil)

    assert_equal({ operation: "X", outcome: :succeeded, actor_id: "1", error: nil }, entry.to_h)
    assert_equal Place.new(code: "ZA"), Place.new(**Place.new(code: "ZA").to_h)
  end

  # **`call_later` refuses what `call` refuses.** Without building the operation it answered
  # `success(:enqueued)` for arguments that could never run, which then burned the whole
  # retry budget failing.
  def test_call_later_asserts_its_arguments_before_enqueuing
    assert_raises(ArgumentError) do
      enqueued { Slow.call_later(actor: NAMED, amount: "not an integer") }
    end
    assert_empty OperationJob.enqueued
  end

  # **An actor that cannot be named cannot be deferred.** It used to be dropped in silence:
  # the caller was told `success(:enqueued)`, the job died "requires an actor", exhausted its
  # retries and wrote no audit entry at all.
  def test_call_later_refuses_an_actor_it_could_not_rebuild
    error = assert_raises(ArgumentError) do
      enqueued { Slow.call_later(actor: ANYONE, amount: 5) }
    end

    assert_includes error.message, "needs an actor with an id to defer"
    assert_empty OperationJob.enqueued
  end

  def test_call_later_refuses_an_actor_whose_id_is_nil
    assert_raises(ArgumentError) do
      enqueued { Slow.call_later(actor: Named.new(nil), amount: 5) }
    end
    assert_empty OperationJob.enqueued
  end

  # `to_h` is the instance variables, which is the round trip only when they are the keywords.
  # The comment used to promise more than that.
  def test_to_h_does_not_round_trip_a_shape_that_renames_its_fields
    renaming = Class.new(Shape) do
      def initialize(from:)
        @starts_at = typed(from, String)
      end
    end

    assert_equal({ starts_at: "x" }, renaming.new(from: "x").to_h)
    assert_raises(ArgumentError) { renaming.new(**renaming.new(from: "x").to_h) }
  end

  # **Every writing door, not just `Command`.** The audit call is in four base classes and
  # only one of them was ever exercised — so three could have lost it and every check here
  # would have stayed green, which is exactly the hole this suite was told it had.
  class AuditedCommand < Command
    def initialize; end

    def call
      success(1)
    end
  end

  class AuditedIo < IoCommand
    def initialize; end

    def call
      success(1)
    end
  end

  class AuditedLegacy < LegacyCommand
    def initialize; end

    def call
      success(1)
    end
  end

  class AuditedFlow < Workflow
    STEPS = [AuditedCommand].freeze

    def initialize; end

    def call
      success(1)
    end
  end

  AUDITED_DOORS = [AuditedCommand, AuditedIo, AuditedLegacy, AuditedFlow].freeze

  # A workflow asks `permissions`, a command asks `permission`; an actor that says no to
  # everything refuses both without the test having to know which.
  Refuser = Struct.new(:nothing) do
    def may?(_permission)
      false
    end
  end

  REFUSER = Refuser.new(nil).freeze

  def test_every_writing_door_records_what_it_did
    AUDITED_DOORS.each do |door|
      entries = audited { door.call(actor: ANYONE) }

      assert_equal 1, entries.length, door.name
      assert_equal :succeeded, entries.first.outcome, door.name
      assert_equal door.name, entries.first.operation, door.name
    end
  end

  # The entry nobody has when they need it, on every door.
  def test_every_writing_door_records_a_refusal
    AUDITED_DOORS.each do |door|
      entries = audited { door.call(actor: REFUSER) }

      assert_equal :refused, entries.first.outcome, door.name
      assert_equal :forbidden, entries.first.error, door.name
    end
  end

  # **Derived, so a new door cannot ship unaudited.** The doors exercised above must be
  # exactly the generated base classes that contain an audit call — add a fifth that records
  # and this reddens until it is covered.
  def test_every_generated_door_that_records_is_exercised
    recording = Shipshape::Install::FILES.select do |name|
      path = File.expand_path("../../lib/shipshape/templates/#{name}.rb.tt", __dir__)
      File.file?(path) && File.read(path).include?("AuditLog.record")
    end

    covered = AUDITED_DOORS.map { |door| door.superclass.name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase }

    assert_equal recording.sort, covered.sort
  end

  def test_an_error_code_is_a_name_not_a_sentence
    assert_raises(ArgumentError) { Result.failure("something went wrong") }
  end

  def test_boolean_is_a_name_and_reopens_nothing
    refute_includes true.class.ancestors, Boolean
    assert_equal "Boolean", Boolean.to_s
  end
  # `OperationSurface` is the exact form of `one-operation-one-class`, and these are the
  # cases the cops cannot reach. A cop reads source; every one of these is invisible there
  # and obvious here.
  DOORS = [Command, Query, Workflow, IoQuery, IoCommand, LegacyQuery, LegacyCommand].freeze

  def additions(operation)
    OperationSurface.public_additions(operation, DOORS)
  end

  def test_a_clean_operation_adds_nothing
    operation = Class.new(Command) do
      def call; end

      private

      def total; end
    end

    assert_empty additions(operation)
  end

  def test_a_public_helper_is_an_addition
    operation = Class.new(Command) do
      def call; end

      def total; end
    end

    assert_equal %i[total], additions(operation)
  end

  # The entry point is public and is not an addition: which of the two an operation
  # implements is what decides whether it is checked.
  def test_neither_entry_point_counts
    assert_empty additions(Class.new(Command) { def call; end })
    assert_empty additions(Class.new(Command) { def anonymous_call; end })
  end

  # **The case no cop can see.** The module is named by a variable, so nothing reading source
  # knows this class includes it.
  def test_a_module_included_through_a_variable_is_still_seen
    helpers = Module.new { def total; end }
    operation = Class.new(Command) do
      include helpers

      def call; end
    end

    assert_equal %i[total], additions(operation)
  end

  def test_a_method_made_by_define_method_is_still_seen
    operation = Class.new(Command) do
      def call; end

      define_method(:total) { 1 }
    end

    assert_equal %i[total], additions(operation)
  end

  def test_a_public_class_method_is_an_addition
    operation = Class.new(Command) do
      def self.build; end

      def call; end
    end

    assert_equal %i[build], additions(operation)
  end

  # Measured from the door rather than from `superclass`, so a hierarchy that broke
  # `an-operation-is-a-leaf` does not also make this go quiet. Comparing a leaf against its
  # parent operation would have reported nothing at all.
  def test_a_second_level_still_reports_what_the_first_added
    parent = Class.new(Command) do
      def call; end

      def total; end
    end
    child = Class.new(parent)

    assert_equal %i[total], additions(child)
  end

  def test_something_that_is_not_an_operation_is_left_alone
    assert_empty additions(Class.new { def total; end })
  end
  # **A shape never holds a record.** The call graph stops a shape naming one; only this
  # stops one arriving as an argument, where the source at the shape says nothing at all.
  RECORD = Class.new(ActiveRecord::Base)

  class Holder < Shape
    def initialize(thing:)
      @thing = thing
    end
  end

  def test_a_shape_refuses_a_record_handed_to_it
    error = assert_raises(TypeError) { Holder.new(thing: RECORD.new) }

    assert_includes error.message, "This is the presentation layer"
    assert_includes error.message, "@thing"
  end

  def test_a_shape_refuses_a_relation
    assert_raises(TypeError) { Holder.new(thing: ActiveRecord::Relation.new) }
  end

  # `lines: person.orders` is how this arrives far more often than a bare record.
  def test_a_shape_refuses_a_record_inside_a_collection
    assert_raises(TypeError) { Holder.new(thing: [RECORD.new]) }
    assert_raises(TypeError) { Holder.new(thing: { rows: [RECORD.new] }) }
  end

  def test_a_shape_takes_values_and_other_shapes
    assert Holder.new(thing: "ZA")
    assert Holder.new(thing: Place.new(code: "ZA"))
    assert Holder.new(thing: [1, 2, 3])
  end

  # The refusal must not cost the value semantics the rest of the file relies on.
  def test_construction_still_answers_a_working_shape
    assert_equal Holder.new(thing: 1), Holder.new(thing: 1)
    refute_equal Holder.new(thing: 1), Holder.new(thing: 2)
  end
  # A view component is the other presentation kind, and the matrix gives it one row:
  # `shape`. A component holding a record renders a template that queries — the N+1 nobody
  # can find, because the call causing it is in an `.erb` file and names nothing.
  class Panel < ApplicationViewComponent
    def initialize(thing:)
      @thing = typed(thing, Object)
    end
  end

  # Refused at the argument, because the component typed it — the same guard every kind gets
  # from `TypedArguments`, not a rule about components.
  def test_a_view_component_refuses_a_record_too
    error = assert_raises(ArgumentError) { Panel.new(thing: RECORD.new) }

    assert_includes error.message, "is not an argument"
  end

  def test_a_view_component_takes_values_and_shapes
    assert Panel.new(thing: Place.new(code: "ZA"))
  end

  # One rule, one implementation. Two copies of it is how the two kinds come to disagree.
  def test_both_presentation_kinds_refuse_through_the_same_module
    assert_includes Shape.singleton_class.ancestors, HoldsNoRecords
    assert_includes ApplicationViewComponent.singleton_class.ancestors, HoldsNoRecords
  end
  # **A record is never an argument — into anything.** Every generated base class includes
  # `TypedArguments`, so the one guard covers every kind at the one moment every argument
  # passes through.
  class Typing
    include TypedArguments

    def assert(value)
      typed(value, Object)
    end

    def assert_as_record(value)
      typed(value, RECORD)
    end

    def assert_many(values)
      typed_array(values, Object)
    end
  end

  def test_typed_refuses_a_record
    error = assert_raises(ArgumentError) { Typing.new.assert(RECORD.new) }

    assert_includes error.message, "is a record, and a record is not an argument"
  end

  # Declaring the record type is not a licence. It is the clearest statement of the defect,
  # so it is refused before the type is matched rather than waved through by matching.
  def test_declaring_the_record_type_does_not_permit_it
    assert_raises(ArgumentError) { Typing.new.assert_as_record(RECORD.new) }
  end

  def test_typed_refuses_a_relation_and_a_collection_of_records
    assert_raises(ArgumentError) { Typing.new.assert(ActiveRecord::Relation.new) }
    assert_raises(ArgumentError) { Typing.new.assert_many([RECORD.new]) }
  end

  def test_typed_still_takes_values_and_shapes
    assert_equal "ZA", Typing.new.assert("ZA")
    assert_equal [1, 2], Typing.new.assert_many([1, 2])
  end

  # **The two guards are not one guard twice**, and this is the case that separates them: a
  # class that never calls `typed` gets nothing from the argument check, and the sweep is
  # what catches it.
  class Untyped < Shape
    def initialize(thing:)
      @thing = thing
    end
  end

  def test_the_sweep_catches_what_never_passed_through_typed
    error = assert_raises(TypeError) { Untyped.new(thing: RECORD.new) }

    assert_includes error.message, "This is the presentation layer"
  end
end
