# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # `a-kind-is-inherited-not-only-placed`: `Kinds#for_path`'s own path fallback is not a
      # promise every other cop here is entitled to trust silently.
      class KindIsInheritedNotOnlyPlaced < Base
        include ReadsKinds

        # One example per kind, naming that kind's own declared base rather than a fixed
        # one: copying `SHAPE` used to hand back a command wherever it fired, base and all.
        INSTEAD = {
          "workflow" => <<~RUBY,
            class SettleOrder < %<base>s
              def call
                charged = ChargeCard.call(actor: actor, order: @order)
                return charged if charged.value.nil?

                RecordPayment.call(actor: actor, order: @order, charge: charged.value)
              end
            end
          RUBY
          "command" => <<~RUBY,
            class SettleInvoice < %<base>s
              def call
                success(...)
              end
            end
          RUBY
          "query" => <<~RUBY,
            class FindBooking < %<base>s
              def call
                row = BookingRecord.find_by(id: @id)
                row && Booking.from(row)
              end
            end
          RUBY
          "io_command" => <<~RUBY,
            class ChargeCard < %<base>s
              def call
                success(@gateway.charge(@order.total))
              end
            end
          RUBY
          "io_query" => <<~RUBY,
            class ChargeStatus < %<base>s
              def call
                Charge.from(@gateway.status(@reference))
              end
            end
          RUBY
          "legacy_command" => <<~RUBY,
            class SettleLegacyInvoice < %<base>s
              def call
                success(...)
              end
            end
          RUBY
          "legacy_query" => <<~RUBY,
            class FindLegacyBooking < %<base>s
              def call
                LegacyBookingRecord.find_by(id: @id)
              end
            end
          RUBY
          "shape" => <<~RUBY,
            class Money < %<base>s
              def format
                readable_amount
              end
            end
          RUBY
          "record" => <<~RUBY,
            class BookingRecord < %<base>s
            end
          RUBY
          "view_component" => <<~RUBY,
            class BookingSummary < %<base>s
              def initialize(booking:)
                @booking = booking
              end
            end
          RUBY
          "entry_point" => <<~RUBY,
            class ProcessBookingJob < %<base>s
              def perform(booking_id)
                NotifyBooking.call(booking_id: booking_id)
              end
            end
          RUBY
          "request_handling" => <<~RUBY,
            class BookingsController < %<base>s
              def create
                render json: CreateBooking.call(**params)
              end
            end
          RUBY
        }.freeze

        # `Kinds` may configure a kind neither this hash lists.
        GENERIC_INSTEAD = <<~RUBY.freeze
          class Example < %<base>s
            def call
              success(...)
            end
          end
        RUBY
        INSTEAD.freeze

        def on_class(node)
          return unless declares_this_file?(node)

          bases = base_names
          return if bases.empty? || names_a_base?(node, bases)

          check_inheritance(node, bases)
        end

        private

        def names_a_base?(node, bases)
          bases.any? { |base| same_name?(base, fully_qualified(node)) }
        end

        def check_inheritance(node, bases)
          parent = node.parent_class

          return add_offense(node.identifier, message: unrooted(node, bases)) if parent.nil?
          return unless parent.const_type?

          name = parent.source.sub(/\A::/, "")
          return unless rooted_in_a_base?(name, bases) == false

          add_offense(parent, message: not_a_base(node, name, bases))
        end

        def unrooted(node, bases)
          kind = kind_of_inspected_file
          explain(
            "`#{node.identifier.source}` is #{article(kind)} #{kind} by placement, and " \
            "names no superclass at all.",
            because: "Every cop gated on `#{kind}` assumes a class here already inherited " \
                     "#{bases_or(bases)} — that inheritance is where `#{kind}`'s own " \
                     "guarantees actually live, not the directory. A path match with " \
                     "nothing behind it is governed in name only: this file reads as " \
                     "`#{kind}` to every one of those cops and carries none of what " \
                     "`#{kind}` means.",
            instead: instead(bases),
          )
        end

        def not_a_base(node, name, bases)
          kind = kind_of_inspected_file
          explain(
            "`#{node.identifier.source}` inherits `#{name}`, and neither `#{name}` nor " \
            "anything it inherits is #{bases_or(bases)}.",
            because: "`BaseClasses` is what tells `#{kind}` apart from a plain class filed " \
                     "in the same tree. A superclass outside that list, and outside " \
                     "everything that list itself resolves to, means this file is " \
                     "`#{kind}` to every cop here without ever inheriting what the kind is.",
            instead: instead(bases),
          )
        end

        def instead(bases)
          template = INSTEAD.fetch(kind_of_inspected_file, GENERIC_INSTEAD)
          format(template, base: bases.first)
        end

        # Three answers, not two: `true` is rooted (fine), `false` is a superclass this
        # canon fully traced to a real file whose chain never reaches a declared base (the
        # one case this law can actually prove), and `nil` is a superclass it could not
        # resolve at all — a gem base, a constant holding one, a base class installed
        # outside every `Kinds` tree — which is left alone rather than guessed at.
        def rooted_in_a_base?(name, bases, seen = [])
          return false if name.nil? || seen.include?(name)
          return true if bases.any? { |base| same_name?(base, name) }

          file = kinds.file_for_constant(name)
          return nil unless file

          rooted_in_a_base?(kinds.superclass_of(file), bases, seen + [name])
        end

        # The one class whose fully-qualified name resolves back to this exact file — never
        # a sibling, a nested helper, or a `Struct.new` with no name of its own to resolve.
        def declares_this_file?(node)
          return false unless kind_of_inspected_file

          resolved = kinds.file_for_constant(fully_qualified(node))
          return false unless resolved

          File.expand_path(resolved) == expanded_path
        end

        # Namespace and all, exactly as `mixins_add_nothing_public.rb` builds it: reading
        # `node.identifier` alone never saw `module Billing; class Invoice`.
        def fully_qualified(node)
          outer = node.each_ancestor(:module, :class).map { |scope| scope.identifier.source }

          (outer.reverse + [node.identifier.source]).join("::").sub(/\A::/, "")
        end

        def expanded_path
          @expanded_path ||= File.expand_path(processed_source.file_path)
        end

        def base_names
          Array(settings.base_classes[kind_of_inspected_file])
        end

        def same_name?(declared, name)
          declared.split("::").last == name.split("::").last
        end

        def bases_or(bases)
          bases.map { |base| "`#{base}`" }.join(" or ")
        end

        def article(kind)
          kind.to_s.start_with?("a", "e", "i", "o", "u") ? "an" : "a"
        end
      end
    end
  end
end
