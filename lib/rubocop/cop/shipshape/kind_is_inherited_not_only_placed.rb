# frozen_string_literal: true

require "rubocop/cop/shipshape/reads_kinds"

module RuboCop
  module Cop
    module Shipshape
      # `a-kind-is-inherited-not-only-placed`: `Kinds#for_path`'s own path fallback is not a
      # promise every other cop here is entitled to trust silently.
      class KindIsInheritedNotOnlyPlaced < Base
        include ReadsKinds

        SHAPE = <<~RUBY
          class SettleInvoice < Command   # the base BaseClasses declares for `command`
            def call
              success(...)
            end
          end
        RUBY

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
          return if rooted_in_a_base?(name, bases)

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
            instead: SHAPE,
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
            instead: SHAPE,
          )
        end

        def rooted_in_a_base?(name, bases, seen = [])
          return false if name.nil? || seen.include?(name)
          return true if bases.any? { |base| same_name?(base, name) }

          file = kinds.file_for_constant(name)
          return false unless file

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
