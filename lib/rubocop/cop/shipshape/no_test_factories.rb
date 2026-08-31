# frozen_string_literal: true

require "rubocop/cop/shipshape/explains"

module RuboCop
  module Cop
    module Shipshape
      # Holds `no-test-factories`.
      #
      # A factory is a second way to construct domain state, running beside the commands and
      # obeying none of their rules: no permission checked, no argument typed, no audit entry,
      # no sequence respected.
      #
      # **So it can build a state the application cannot.** A confirmed booking with no
      # payment, an order line priced in a currency its order does not use — a row the commands
      # would refuse, which a test then asserts behaviour on. That test passes, stays green for
      # years, and describes a system that does not exist. The inverse is quieter: if a command
      # cannot reach a state it should, the factory reached it instead and nothing noticed.
      #
      # A test builds what it needs by calling operations. Setup pain is then a signal about
      # the model rather than a problem to be tooled around.
      #
      # WHAT IT DOES NOT CATCH: **it reads how state is built, never whether the state is
      # right.** A test calling the correct operations to reach a state nobody wants passes.
      #
      # It knows the factory libraries by name, so a helper of your own — `def a_booking(...)`
      # wrapping a raw `create!` — is not caught, and that is the shape a suite reaches for the
      # day after this lands. A bare `Record.create!` in a test is not matched either:
      # separating it from a legitimately seeded reference row needs a judgement no cop makes.
      #
      # @example
      #   # bad — sets columns, obeys no rule, and may build what no command could
      #   booking = create(:booking, status: "confirmed")
      #
      #   # bad — the same door, named differently
      #   booking = FactoryBot.create(:booking)
      #   booking = Fabricate(:booking)
      #
      #   # bad — fixtures are the same second construction, loaded earlier
      #   fixtures :all
      #
      #   # good — the state exists because the application can produce it
      #   booking = CreateBooking.test_call(offer_id: offer.id).value
      #   ConfirmBooking.test_call(booking_id: booking.id)
      class NoTestFactories < Base
        include Explains

        # `create(:booking)` — the bare-word DSL, which is what a suite actually contains.
        BUILDERS = %i[create create_list build build_list build_stubbed attributes_for].freeze
        LIBRARIES = %w[FactoryBot FactoryGirl Fabricate Fabricator].freeze
        FIXTURES = %i[fixtures set_fixture_class].freeze

        def on_send(node)
          return add_offense(node, message: fixture_message) if fixtures?(node)
          return unless factory?(node)

          add_offense(node, message: factory_message(node.method_name))
        end

        private

        # A symbol first argument is what separates `create(:booking)` from `create(record)`
        # and from a `build` that means something else entirely.
        def factory?(node)
          return true if library?(node)

          BUILDERS.include?(node.method_name) && node.receiver.nil? && node.first_argument&.sym_type?
        end

        def library?(node)
          receiver = node.receiver
          return true if receiver.nil? && node.method_name == :Fabricate

          receiver&.const_type? && LIBRARIES.include?(receiver.source.sub(/\A::/, ""))
        end

        def fixtures?(node)
          FIXTURES.include?(node.method_name) && node.receiver.nil? && node.arguments.any?
        end

        def factory_message(name)
          explain(
            "`#{name}` builds domain state without going through an operation.",
            because: "A factory sets columns; a command enforces which combinations of them " \
                     "are legal. So a factory can produce a row the application cannot — a " \
                     "confirmed booking with no payment — and a test asserting behaviour on " \
                     "that row asserts behaviour on fiction. It passes, it stays green, and " \
                     "it describes a system that does not exist. The inverse is quieter: if " \
                     "a command cannot reach a state it should, nothing notices, because the " \
                     "factory reached it instead.",
            instead: CALLED,
          )
        end

        def fixture_message
          explain(
            "Fixtures build domain state without going through an operation.",
            because: "They are the same second construction as a factory, loaded earlier and " \
                     "shared across every test in the suite — so a row one test needed is a " \
                     "row every other test silently depends on, and no operation vouches for " \
                     "any of it. State that arrives before the test starts cannot be read " \
                     "from the test.",
            instead: CALLED,
          )
        end

        CALLED = <<~RUBY
          # the state exists because the application can produce it, and the setup has
          # exercised the operations that produce it
          booking = CreateBooking.test_call(offer_id: offer.id).value
          ConfirmBooking.test_call(booking_id: booking.id)

          # reference data no operation creates is seeded, not factoried
          currency = Currency.find_by!(code: "ZAR")
        RUBY
      end
    end
  end
end
