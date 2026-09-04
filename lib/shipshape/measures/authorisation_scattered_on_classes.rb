# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    class AuthorisationScatteredOnClasses
      TITLE = "Authorisation decided on a class"
      LAW = "a-permission-is-the-class-name"
      WHY = "Each of these answers who may do something, and none of them is a permission " \
            "anything can enumerate. No screen can offer them, no grant can revoke them, and " \
            "a refusal leaves no trace."

      NOUN = "public methods on classes"

      # Every clause asks, or an unanchored `_by_user` catches `ban_by_user_for_reason!`, which
      # does the thing. Being on this list is what makes a name read as authorisation; whether
      # one is auth or a setting is the reader's call, and the finding.
      PERMISSION = /\A(?:can|may|is_allowed|allowed|permitted|authorised|authorized)_|
                    _by_user\?\z|_by\?\z|able_by_|
                    \A(?:is_)?(?:admin|owner|moderator|staff|superuser)\?\z/x

      SUBJECT = "classes under `app/`"

      def subjects(sources)
        governed(sources).length
      end

      def population(sources)
        governed(sources).sum { |source| ClassReading.classes(source).sum { |node| public_names(node).length } }
      end

      def call(sources)
        governed(sources).flat_map do |source|
          ClassReading.classes(source).flat_map do |node|
            deciders(node).map do |method|
              Finding.new(relative: source.relative, line: method.loc.line,
                          label: "##{method.method_name}",
                          context: { subject: ClassReading.name_of(node) })
            end
          end
        end
      end

      OPERATION_TREES = %w[app/deeds/ app/questions/ app/workflows/ app/operations/].freeze

      def governed(sources)
        sources.select do |source|
          source.relative.start_with?("app/") &&
            OPERATION_TREES.none? { |tree| source.relative.start_with?(tree) }
        end
      end

      private

      def deciders(node)
        public_names(node).select { |method| method.method_name.to_s.match?(PERMISSION) }
      end

      def public_names(node)
        ClassReading.public_methods_of(node)
      end
    end
  end
end
