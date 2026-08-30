# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # Holds the second half of `personal-data-is-declared-and-erasable`.
      #
      # **An association with no `dependent:` decides nothing, and the default is to leave the
      # children behind.** Delete a user and their comments remain, pointing at an id that no
      # longer resolves. For an erasure request that is the whole failure: the row the person
      # asked about is gone, and everything they wrote is still there with their name on it.
      #
      # The point is not that `:destroy` is right. Often it is not — comments usually should
      # survive, anonymised. **The point is that nobody chose.** `dependent:` is where the
      # choice is written, and an association without one is the only shape where the answer
      # is decided by ActiveRecord's default rather than by a person.
      #
      # This is also the cheapest erasure guard there is: it needs no inventory, no
      # declaration and no schema — the answer is in the association line.
      #
      # WHAT IT DOES NOT CATCH: whether the option chosen is the right one. `dependent:
      # :destroy` on something that should have been anonymised passes, and so does
      # `:nullify` on a column the schema declares NOT NULL — which fails at runtime, on the
      # delete, which is the worst moment to find out. It says nothing about rows in another
      # database, another service, or a warehouse. **Tests are exempt.**
      #
      # @example
      #   # bad — the children outlive the parent and nobody decided that
      #   has_many :comments
      #
      #   # good — any of these, because each one is a decision
      #   has_many :comments, dependent: :destroy
      #   has_many :comments, dependent: :nullify
      #   has_many :comments, dependent: :restrict_with_error
      class AssociationsSurviveErasure < Base
        include ReadsKinds

        # The associations that own children. `belongs_to` points the other way — the row it
        # names is not this row's to delete.
        ASSOCIATIONS = %i[has_many has_one has_and_belongs_to_many].freeze

        def on_send(node)
          return unless node.receiver.nil?
          return unless associations.include?(node.method_name)
          return unless one_of?(governed_kinds)
          return if decided?(node)

          add_offense(node, message: message_for(node.method_name, name_of(node)))
        end

        private

        def decided?(node)
          options = node.arguments.find(&:hash_type?)
          return false if options.nil?

          options.keys.any? { |key| key.respond_to?(:value) && key.value == :dependent }
        end

        def name_of(node)
          first = node.first_argument
          first.respond_to?(:value) ? first.value.to_s : "them"
        end

        def message_for(association, name)
          explain(
            "`#{association} :#{name}` does not say what happens to #{name} when this row is " \
            "deleted, so the answer is ActiveRecord's default: they are left behind.",
            because: "For an erasure request that is the whole failure — the row the person " \
                     "asked about is gone, and everything they wrote is still there with " \
                     "their name on it, pointing at an id that no longer resolves. The " \
                     "problem is not that `:destroy` is missing; it is often the wrong " \
                     "answer. The problem is that nobody chose, and `dependent:` is the only " \
                     "place that choice can be written down.",
            instead: <<~RUBY,
              has_many :#{name}, dependent: :destroy              # they go with it
              has_many :#{name}, dependent: :nullify              # they stay, unlinked
              has_many :#{name}, dependent: :restrict_with_error  # deletion is refused

              # they stay and are anonymised: that is a command, not an option — and the
              # column it overwrites is what app/shipshape/personal_data.rb marks :anonymise
              has_many :#{name}, dependent: :restrict_with_error
            RUBY
          )
        end

        def associations
          @associations ||= cop_config.fetch("Associations", ASSOCIATIONS.map(&:to_s)).map(&:to_sym)
        end

        def governed_kinds
          cop_config.fetch("Kinds", %w[record])
        end
      end
    end
  end
end
