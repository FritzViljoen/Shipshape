# frozen_string_literal: true

require "shipshape/measures/finding"

module Shipshape
  module Measures
    # Classes with more than one public method, outside controllers and mailers.
    #
    # Each extra public method is a second thing the class does and a second reason for it
    # to change. This is the god object counted early, while it is still four methods rather
    # than a hundred and thirteen columns — and it is the measure that says how much work
    # splitting into commands and queries would actually be.
    #
    # Controllers are excluded because a controller's actions are one job, dispatch, spelled
    # once per route. `RequestHandlingThatDecides` is the measure that speaks to those.
    class ClassesDoingSeveralThings
      TITLE = "Classes doing several things"
      LAW = "one-operation-one-class"
      WHY = "Every extra public method is a second reason for the class to change. This is " \
            "the god object counted while it is still small."

      NOUN = "classes"

      def population(sources)
        sources.reject { |source| excluded?(source) }.sum { |source| ClassReading.classes(source).length }
      end

      def exemplars(sources)
        sources.reject { |source| excluded?(source) }.flat_map do |source|
          ClassReading.classes(source).select { |node| ClassReading.public_methods_of(node).length == 1 }.map do |node|
            Finding.new(relative: source.relative, line: node.loc.line,
                        label: "#{ClassReading.name_of(node)} — one public method")
          end
        end
      end

      EXCLUDED = %w[controllers mailers mailboxes channels jobs].freeze
      NOISE = 3

      def call(sources)
        sources.reject { |source| excluded?(source) }.flat_map do |source|
          ClassReading.classes(source).map { |node| finding(source, node) }.compact
        end
      end

      private

      def finding(source, node)
        count = ClassReading.public_methods_of(node).length
        return nil if count <= 1

        Finding.new(
          relative: source.relative,
          line: node.loc.line,
          label: "#{ClassReading.name_of(node)} — #{count} public methods#{" (worth a look)" if count > NOISE}",
        )
      end

      def excluded?(source)
        EXCLUDED.include?(source.relative.split("/")[1])
      end
    end
  end
end
