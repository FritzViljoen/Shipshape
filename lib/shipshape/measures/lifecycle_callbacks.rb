# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Persistence lifecycle callbacks.
    #
    # The purest form of action at a distance in a Rails application: the caller reads one
    # method, `save`, and gets several, in an order nothing states, with any failure among
    # them attributed to the save.
    #
    # This number matters out of proportion to its size. A codebase with callbacks cannot be
    # read by following calls, which is the one thing both a new developer and an agent
    # depend on.
    class LifecycleCallbacks
      TITLE = "Lifecycle callbacks"
      LAW = "no-lifecycle-callbacks"
      WHY = "The caller reads one method and gets several, in an order nothing states. A " \
            "codebase with these cannot be read by following calls."

      NOUN = "files under app/models"
      # Findings are sites, and many land in one file, so the clean count subtracts files.
      UNIT = :file

      def population(sources)
        models(sources).length
      end

      def exemplars(sources)
        models(sources).reject { |source| registrations(source).any? }.map do |source|
          Finding.new(relative: source.relative, line: 1, label: "no callbacks")
        end
      end

      def models(sources)
        sources.select { |source| source.relative.start_with?("app/models/") }
      end

      HOOKS = %i[
        before_validation after_validation
        before_save around_save after_save
        before_create around_create after_create
        before_update around_update after_update
        before_destroy around_destroy after_destroy
        after_commit after_rollback after_initialize after_find after_touch
      ].freeze

      def call(sources)
        sources.flat_map do |source|
          registrations(source).map do |node|
            Finding.new(relative: source.relative, line: node.loc.line, label: node.method_name.to_s)
          end
        end
      end

      private

      def registrations(source)
        found = []
        ClassReading.walk(source.ast) do |node|
          next unless node.send_type? && node.receiver.nil?

          found << node if HOOKS.include?(node.method_name)
        end
        found
      end
    end
  end
end
