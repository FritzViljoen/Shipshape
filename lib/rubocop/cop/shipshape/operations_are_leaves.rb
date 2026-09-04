# frozen_string_literal: true

require "shipshape/install"
require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      class OperationsAreLeaves < Base
        include ReadsKinds

        DOOR = :call

        ONE_LEVEL = <<~RUBY
          # one level from the base class, always
          class AdminUpload < Deed
            def call
              # what was shared is a collaborator, not an ancestor
              Upload.call(file: @file)
            end
          end
        RUBY

        INSTANCE = <<~RUBY
          # define the instance method; the base class calls it
          class SettleInvoice < Deed
            def call
              success(...)
            end
          end
        RUBY

        def on_class(node)
          return unless one_of?(governed_kinds)

          check_depth(node)
          check_door(node)
        end

        private

        def check_depth(node)
          parent = node.parent_class
          return unless parent&.const_type?

          name = parent.source.sub(/\A::/, "")
          # A base class filed with its operations is still a base class: stratum keeps
          # `Deed` in `app/deeds/`, so every correct operation looked like a second level.
          return if base_class?(name)

          # Only our own hierarchy has a depth rule: a plain class in `app/questions/` resolves
          # to an operation kind by path alone, and is not this canon's business.
          return unless rooted_in_a_base_class?(name)

          kind = kinds.for_constant(name)
          return unless governed_kinds.include?(kind)

          add_offense(parent, message: too_deep(node.identifier.source, parent.source, kind))
        end

        def check_door(node)
          return unless node.body

          node.body.each_node(:defs).each do |definition|
            next unless definition.method?(DOOR)
            next unless definition.children.first.self_type?

            add_offense(definition, message: door_replaced(node.identifier.source))
          end
        end

        def too_deep(name, parent, kind)
          explain(
            "`#{name}` inherits from `#{parent}`, which is already #{article(kind)} #{kind}.",
            because: "A base class is inherited exactly once. Everything the door decides — " \
                     "the permission check, the transaction, the return-type assertion — it " \
                     "decides for the class in front of it, and a second level inherits " \
                     "those answers without appearing to ask the question. A subclass of an " \
                     "operation that implements `anonymous_call` runs unauthenticated with " \
                     "nothing at its own definition saying so, and the audit for public " \
                     "operations does not name it.",
            instead: ONE_LEVEL,
          )
        end

        def door_replaced(name)
          explain(
            "`#{name}` owns `self.#{DOOR}`, which is the door.",
            because: "The door belongs to the base class, because that is the one place a " \
                     "permission check, a transaction and a return-type assertion can be " \
                     "true of every operation at once. A class that defines its own owns " \
                     "all three alone, and the difference is invisible: every caller still " \
                     "writes `#{name}.call(...)`.",
            instead: INSTANCE,
          )
        end

        def rooted_in_a_base_class?(name)
          file = kinds.file_for_constant(name)
          return false unless file

          grandparent = kinds.superclass_of(file)
          !grandparent.nil? && ours?(grandparent)
        end

        def base_class?(name)
          declared?(settings.base_classes.values.flatten, name)
        end

        # Only the base classes shipshape installs, derived from what the installer writes so
        # it cannot drift. Two levels below `ApplicationMailer` is Rails' business.
        def ours?(name)
          declared?(installed_base_classes, name)
        end

        def installed_base_classes
          @installed_base_classes ||=
            governed_kinds.flat_map { |kind| Array(settings.base_classes[kind]) }
                          .select { |declared| ::Shipshape::Install::FILES.include?(underscore(declared)) }
        end

        def underscore(name)
          name.split("::").last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end

        def declared?(names, name)
          simple = name.split("::").last

          names.any? { |declared| declared.split("::").last == simple }
        end

        def article(kind)
          kind.to_s.start_with?("a", "e", "i", "o", "u") ? "an" : "a"
        end

        def governed_kinds
          cop_config.fetch(
            "Kinds",
            %w[workflow deed question io_deed io_question legacy_deed legacy_question],
          )
        end
      end
    end
  end
end
