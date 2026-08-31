# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds `persistence-holds-no-behaviour`.
      #
      # A record declares its columns and its associations. Nothing else. A method here is
      # reachable from everywhere a record is, which is how one concern after another settles
      # on the same class until it has 113 columns and nobody can say what it is for.
      #
      # WHAT IT DOES NOT CATCH: it separates a filtering scope from a rule-bearing one by
      # one syntactic test — whether the block *calls* another class. A constant used as a
      # value is a filter and passes; a rule expressed without naming a class passes too. It sees the record tree only — behaviour moved into a helper, a module
      # included from outside, or a query object filed elsewhere is not covered. And it says
      # nothing about whether the record's columns belong together, which is the actual
      # god-object question and the one no check answers.
      #
      # @example
      #   # bad — a rule reachable from everywhere a BookingRecord is
      #   class BookingRecord < ApplicationRecord
      #     def total = lines.sum(&:amount) * (1 + tax_rate)
      #   end
      #
      #   # good — the record maps rows; the operation computes
      #   class TotalBooking < Query
      #     def call
      #       success(BookingRecord.find(@id).lines.sum(&:amount) * (1 + @tax_rate))
      #     end
      #   end
      class PersistenceHoldsNoBehaviour < Base
        include ReadsKinds
        include VisibilityHelp

        def on_def(node)
          return unless one_of?(record_kinds)
          # The law says "any public method". A private helper is still behaviour, but it
          # is not reachable from everywhere a record is, which is the harm being named.
          return if node_visibility(node) == :private

          add_offense(node, message: message_for("`##{node.method_name}`"))
        end

        def on_defs(node)
          return unless one_of?(record_kinds)

          add_offense(node, message: message_for("`.#{node.method_name}`"))
        end

        # `scope :recent, -> { where(...) }` is a filter. `scope :billable, -> { joins(...)
        # .merge(Other.rule) }` reaches another class, and the law says that one passes.
        #
        # **`default_scope` is judged on neither test**, because its harm is not the one this
        # law usually names. It is ambient state wearing a declaration: a filter that enters
        # every read without being called for, and attributes that leave with every `create`
        # without being handed in. That is `nothing-travels-off-the-call-path` in both
        # directions, declared on a record — which is why it is caught here, where it is
        # written, rather than at the thousand call sites where it acts.
        # **`delegate` is exempt from `code-is-written-not-generated`**, which draws its line
        # at the framework's public conventions and uses this macro to draw it. That line
        # holds: a Rails reader knows what `delegate` does. It says nothing about a record
        # being allowed to have the methods, and this law does.
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

        # Reaching *into* another class means calling it: `SupplierRecord.active`. A
        # constant used as a value — `where(state: Booking::ACTIVE)` — is a filter on this
        # table's own column, which the law explicitly permits, and failing it was this
        # cop's worst false positive.
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

        # `delegate ..., private: true` writes what a private `def` writes, and `on_def` exempts
        # that — a private helper is still behaviour, but it is not reachable from everywhere a
        # record is, which is the harm this law names. Flagging one and not the other made the
        # rule depend on which spelling was used.
        def public_delegate?(node)
          return false unless DELEGATORS.include?(node.method_name)

          options = node.arguments.last
          return true unless options.respond_to?(:hash_type?) && options.hash_type?

          options.pairs.none? { |pair| pair.key.value == :private && pair.value.true_type? }
        end

        # `def name; supplier.name; end` is an offence here, and `delegate :name, to: :supplier`
        # writes the same method — so it was the one way left to put behaviour on a record.
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

        # **The example is the thing that gets copied**, so it must not hand the reader the next
        # defect: `Booking.new(supplier_name: ...)` is the flattening `a-shape-is-composed-not-flattened`
        # names, and it is the planted violation in that cop's own canary.
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

        # The one scope that is never written at the call site, so it cannot be read there
        # either. It is also the only one that reaches `create`.
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

        # The filter reads a row's absence rather than a column's NULL: `no-nullable-columns`
        # refuses `cancelled_at` in the first place, so an example filtering on one would
        # prescribe a schema this canon does not allow.
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

        def record_kinds
          cop_config.fetch("Kinds", %w[record])
        end
      end
    end
  end
end
