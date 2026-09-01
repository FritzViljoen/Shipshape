# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      class NoTestFactories < Base
        include ReadsKinds

        # `create(:booking)` — the bare-word DSL, which is what a suite actually contains.
        BUILDERS = %i[create create_list build build_list build_stubbed attributes_for].freeze
        LIBRARIES = %w[FactoryBot FactoryGirl Fabricate Fabricator].freeze
        FIXTURES = %i[fixtures set_fixture_class].freeze

        # The class methods that persist a row, and the messages that persist one already built.
        FABRICATORS = %i[
          create create! find_or_create_by find_or_create_by!
          create_or_find_by create_or_find_by! insert insert!
        ].freeze
        PERSISTS = %i[save save! update update!].freeze

        def on_send(node)
          return add_offense(node, message: fixture_message) if fixtures?(node)
          return add_offense(node, message: factory_message(node.method_name)) if factory?(node)

          fabricated = fabricated_record(node)
          return unless fabricated

          add_offense(node, message: record_message(fabricated))
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

        # `BookingRecord.create!(...)` or `BookingRecord.new(...).save!`, and only where the
        # constant resolves to a record. A helper of the suite's own that happens to answer
        # `create` is not one.
        def fabricated_record(node)
          code = if FABRICATORS.include?(node.method_name)
                   fabrication(node)
                 elsif PERSISTS.include?(node.method_name)
                   deferred_fabrication(node)
                 end

          code if code && record?(code.last)
        end

        def fabrication(node)
          name = constant(node.receiver)

          ["#{name}.#{node.method_name}", name] if name
        end

        def deferred_fabrication(node)
          built = node.receiver
          return unless built.respond_to?(:send_type?) && built.send_type? && built.method_name == :new

          name = constant(built.receiver)

          ["#{name}.new(...).#{node.method_name}", name] if name
        end

        def constant(node)
          node&.const_type? ? node.source.sub(/\A::/, "") : nil
        end

        def record?(name)
          record_kinds.include?(kinds.for_constant(name))
        end

        def record_message(fabricated)
          code, name = fabricated

          explain(
            "`#{code}` writes a row instead of calling the operation that produces one.",
            because: "It is the same second construction a factory is, spelled honestly: no " \
                     "permission is checked, no argument is typed, no rule about which " \
                     "combination of columns is legal runs. So it can persist a row the " \
                     "application cannot — and every assertion after it describes a system " \
                     "that does not exist. The `#{name}` a command would have built is the " \
                     "one worth asserting on.",
            instead: CALLED,
          )
        end

        def record_kinds
          cop_config.fetch("RecordKinds", %w[record])
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
