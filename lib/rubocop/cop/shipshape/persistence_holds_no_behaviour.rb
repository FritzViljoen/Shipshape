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
        def on_send(node)
          return unless node.method_name == :scope
          return unless one_of?(record_kinds)
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
