# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      class PersistenceHoldsNoBehaviour < Base
        include ReadsKinds
        include VisibilityHelp

        # The example is what gets copied, so it must not hand the reader the flattening
        # `a-shape-is-composed-not-flattened` names.
        ASKED = <<~RUBY
          # the record maps rows and nothing else
          class BookingRecord < ApplicationRecord
            belongs_to :supplier_record
          end

          # the query composes: a Booking holds a Supplier, and never copies its columns
          class ShowBooking < Query
            def call
              row = BookingRecord.find(@id)
              success(Booking.new(reference: row.reference, supplier: Supplier.from(row.supplier_record)))
            end
          end
        RUBY

        # A row's absence, not a column's NULL: `no-nullable-columns` refuses `cancelled_at`.
        FILTERED = <<~RUBY
          # the record maps rows, and says nothing about which of them anyone wants
          class BookingRecord < ApplicationRecord
            belongs_to :supplier_record
            has_one :cancellation_record
          end

          # the filter is named, and it is read where it is used
          class ListLiveBookings < Query
            def call
              success(BookingRecord.where.missing(:cancellation_record).map { |row| Booking.from(row) })
            end
          end
        RUBY

        SPLIT = <<~RUBY
          # the record maps rows: columns and associations, nothing else
          class BookingRecord < ApplicationRecord
            belongs_to :supplier_record
            has_many :line_records
          end

          # the domain object is detached, so nobody can query through it by accident
          class Booking < Shape
            def initialize(reference:, lines:)
              @reference = typed(reference, String)
              @lines = typed_array(lines, Booking::Line)
            end
          end

          # and the operation is where deriving happens
          class TotalBooking < Query
            def call
              success(@booking.lines.sum(&:amount) * (1 + @tax_rate))
            end
          end
        RUBY

        def on_def(node)
          return unless one_of?(record_kinds)
          return if node_visibility(node) == :private

          add_offense(node, message: message_for("`##{node.method_name}`"))
        end

        def on_defs(node)
          return unless one_of?(record_kinds)

          add_offense(node, message: message_for("`.#{node.method_name}`"))
        end

        # `default_scope` is judged on neither test: it is ambient state wearing a declaration,
        # entering every read uncalled-for and leaving with every `create`. Caught here, where
        # it is written, rather than at the thousand call sites where it acts.
        DELEGATORS = %i[delegate delegate_missing_to].freeze

        def on_send(node)
          return unless one_of?(record_kinds)
          return add_offense(node, message: default_scope_message) if node.method_name == :default_scope
          return add_offense(node, message: delegate_message(node.method_name)) if public_delegate?(node)
          return unless node.method_name == :scope
          return unless reaches_another_class?(node)

          add_offense(node, message: scope_message(node))
        end

        private

        # A constant used as a value — `where(state: Booking::ACTIVE)` — is a filter on this
        # table's own column, and failing it was this cop's worst false positive.
        def reaches_another_class?(node)
          block = node.each_descendant(:block).first
          return false unless block

          block.each_descendant(:send).any? { |send| send.receiver&.const_type? }
        end

        def message_for(name)
          explain(
            "#{name} is behaviour on a record, which maps rows and holds no rules.",
            because: "A method here is reachable from everywhere a record is — every " \
                     "controller, every view, every job — so there is no boundary deciding " \
                     "who may ask. That is how one concern after another settles on the " \
                     "same class until it has a hundred columns and nobody can say what it " \
                     "is for. The record's shape also becomes whatever the table happens " \
                     "to have, instead of what the domain means.",
            instead: SPLIT,
          )
        end

        # `delegate ..., private: true` writes what a private `def` writes, which `on_def`
        # exempts. Flagging one and not the other made the rule depend on the spelling.
        def public_delegate?(node)
          return false unless DELEGATORS.include?(node.method_name)

          options = node.arguments.last
          return true unless options.respond_to?(:hash_type?) && options.hash_type?

          options.pairs.none? { |pair| pair.key.value == :private && pair.value.true_type? }
        end

        def delegate_message(name)
          explain(
            "`#{name}` puts public methods on a record, which maps rows and holds no rules.",
            because: "It writes the methods `def` would have written, so a record that may " \
                     "not answer `#name` answers it anyway — and the guard reading `def` " \
                     "sees nothing. The method is also somebody else's: the caller depends " \
                     "on a class it never names, and a `nil` in the middle raises " \
                     "`NoMethodError` naming a class the reader was not looking at. " \
                     "`allow_nil: true` answers that by making absence a value, which this " \
                     "canon refuses everywhere else.",
            instead: ASKED,
          )
        end

        # Never written at the call site, so never read there. Also the only one reaching `create`.
        def default_scope_message
          explain(
            "`default_scope` is implicit behaviour: global state on every read, and a distant write on `create`.",
            because: "A named scope is a rule you can see in the chain that used it. This " \
                     "one is not written anywhere it acts. Every association, every `find`, " \
                     "every count silently receives a filter nobody asked for, so a query's " \
                     "result cannot be predicted from the query — the definition of action " \
                     "at a distance. It also sets attributes on `create`, so a record is " \
                     "born carrying a filter's opinion its caller never handed in. Both " \
                     "halves are `nothing-travels-off-the-call-path`, and the escape hatch " \
                     "makes it worse: `unscoped` is a second way to say one read, and now " \
                     "neither the rule nor its exception is visible where the reading is.",
            instead: FILTERED,
          )
        end

        def scope_message(node)
          explain(
            "This scope reaches another class, so it carries a rule rather than a filter.",
            because: "A filter on this table's own columns is part of mapping rows. A " \
                     "scope that knows about another class has encoded a decision, and it " \
                     "is now reachable from everywhere a `#{node.arguments.first.source}` " \
                     "chain can be started — with no boundary deciding who may ask.",
            instead: SPLIT,
          )
        end

        def record_kinds
          cop_config.fetch("Kinds", %w[record])
        end
      end
    end
  end
end
