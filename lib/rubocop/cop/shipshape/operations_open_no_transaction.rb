# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `a-command-is-one-transaction`.
      class OperationsOpenNoTransaction < Base
        include ReadsKinds

        # True for the kind it fires on, not for all seven: `command` and `legacy_command`
        # have a base class that already opened one; a `workflow` spans several and each step
        # owns its own; `io_command` and `io_query` must never hold one open over the wire; a
        # `query` and `legacy_query` read, and a read needs none.
        BECAUSE = {
          "command" => "The generated base class wraps the call in exactly one, opened " \
                       "before the work and after the permission check. A second call here " \
                       "either nests that one or silently widens it, and nobody decided which.",
          "workflow" => "A workflow sequences several transactions, one per step, and each " \
                        "step is the one that owns and covers its own writes. Wrapping steps " \
                        "in a transaction here removes the boundary a step already answers " \
                        "for, silently, and widens what a crash mid-way leaves half done.",
          "io_command" => "A call inside a transaction holds it open over the wire, for " \
                          "however long the outside world takes to answer. This kind exists " \
                          "so that never happens; a transaction written here is the mistake " \
                          "the split from `Command` was made to refuse.",
          "io_query" => "A call inside a transaction holds it open over the wire, for " \
                        "however long the outside world takes to answer, and this kind " \
                        "writes nothing — it answers with shapes, same as `Query` — so " \
                        "there is nothing here for a transaction to protect. One opened " \
                        "here only holds a connection for as long as the remote call takes.",
          "query" => "A read needs no transaction at all. One wrapped around a read holds a " \
                     "connection open for nothing, and the base class already omits it.",
        }
        BECAUSE["legacy_command"] = BECAUSE["command"]
        BECAUSE["legacy_query"] = BECAUSE["query"]

        # `Kinds` may configure a kind neither hash above lists.
        GENERIC_BECAUSE = "An operation opens no transaction of its own. That is true of " \
                          "every kind this cop can be configured to check, whether or not " \
                          "this one has a more specific reason on file."
        BECAUSE.freeze

        INSTEAD = {
          "command" => <<~RUBY,
            # the writes are one act; the base class's transaction already covers them
            class ConfirmBooking < Command
              def call
                @booking.confirm!
                @booking.ledger_entries.create!(amount: @booking.total)
                success(@booking)
              end
            end
          RUBY
          "workflow" => <<~RUBY,
            # each step is idempotent and opens its own transaction; this one opens none
            class SettleOrder < Workflow
              def call
                charged = ChargeCard.call(actor: actor, order: @order)
                return charged if charged.value.nil?

                RecordPayment.call(actor: actor, order: @order, charge: charged.value)
              end
            end
          RUBY
          "io_command" => <<~RUBY,
            # the call to the gateway is never held inside a transaction
            class ChargeCard < IoCommand
              def call
                success(@gateway.charge(@order.total))
              end
            end
          RUBY
          "io_query" => <<~RUBY,
            # the call to the gateway is never held inside a transaction
            class ChargeStatus < IoQuery
              def call
                Charge.from(@gateway.status(@reference))
              end
            end
          RUBY
          "query" => <<~RUBY,
            # a read needs no transaction; the base class already has none
            class FindBooking < Query
              def call
                row = BookingRecord.find_by(id: @id)
                row && Booking.from(row)
              end
            end
          RUBY
        }
        INSTEAD["legacy_command"] = INSTEAD["command"]
        INSTEAD["legacy_query"] = INSTEAD["query"]

        GENERIC_INSTEAD = <<~RUBY.freeze
          # this kind opens no transaction of its own
          class Example
            def call
              @thing.save!
            end
          end
        RUBY
        INSTEAD.freeze

        def on_send(node)
          return unless node.method_name == :transaction
          return unless node.block_node
          return unless one_of?(operation_kinds)
          return unless base_class_transaction?(node)

          add_offense(node, message: message_for(node))
        end

        private

        # A bare call is the base class's own transaction, reached by inheritance. A `record`
        # receiver — or `ActiveRecord::Base` itself, which this configuration classifies as one
        # — spells the same call out. Anything else is a same-named method on an unrelated
        # object: a payment gateway's own API, an association, an attribute reader — and
        # refusing it would ban reading a `transaction` as hard as opening one.
        def base_class_transaction?(node)
          receiver = node.receiver
          return true if receiver.nil?

          name = root_constant(node)
          !name.nil? && record?(name)
        end

        def message_for(node)
          kind = kind_of_inspected_file

          explain(
            "`#{node.method_name}` opens a transaction of its own.",
            because: BECAUSE.fetch(kind, GENERIC_BECAUSE),
            instead: INSTEAD.fetch(kind, GENERIC_INSTEAD),
          )
        end

        def operation_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow command query io_command io_query legacy_command legacy_query],
          )
        end
      end
    end
  end
end
