# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/naming"

module Shipshape
  module Measures
    # Public methods on models, beyond the declarations that describe the table.
    #
    # A record maps rows and holds no rules. Every method here is a rule living on the thing
    # that stores it, reachable from anywhere the record is — which is everywhere — and that
    # reachability is what lets one concern after another settle on the same class until it
    # is a hundred columns wide.
    #
    # Associations, scopes, validations and the rest are declarations about the table, not
    # behaviour, so they are not counted.
    class PersistenceWithBehaviour
      TITLE = "Rules living on persistence"
      LAW = "persistence-holds-no-behaviour"
      WHY = "A rule on a record is reachable from everywhere the record is, which is how " \
            "one concern after another settles on the same class."

      def call(sources)
        models(sources).flat_map do |source|
          ClassReading.classes(source).select { |node| persistence?(node) }.flat_map do |node|
            ClassReading.public_methods_of(node).map do |method|
              Finding.new(
                relative: source.relative,
                line: method.loc.line,
                label: "##{method.method_name}",
                context: { record: ClassReading.name_of(node), method: method.method_name },
              )
            end
          end
        end
      end

      def proposal(findings)
        finding = findings.first
        return nil if finding.nil? || finding.context.nil?

        record = finding.context[:record]
        method = finding.context[:method]
        name = "#{Naming.camel(method.to_s.delete_suffix("?"))}#{record}"

        <<~TEXT
          `#{record}##{method}` is a rule living on the thing that stores it, reachable from
          anywhere a `#{record}` is — which is everywhere. Moved, it becomes callable by name
          and testable without a row:

          ```ruby
          # app/queries/#{Naming.snake(name)}.rb
          class #{name} < Query
            def initialize(#{Naming.snake(record)}:)
              @#{Naming.snake(record)} = typed(#{Naming.snake(record)}, #{record})
            end

            def call
              # the body of #{record}##{method} today
            end
          end
          ```

          Whether it is a Query or a Command depends on whether it reads or writes, and that
          is a judgement this report does not make.
        TEXT
      end

      private

      # Being filed in `app/models` is not the same as being a table. Rails put plain
      # objects there for a decade because there was nowhere else, and counting those here
      # would both inflate this number and mislabel them — they are already reported as
      # classes that inherit from nothing, which is what they actually are.
      BASES = [/\AApplicationRecord\z/, /\AActiveRecord::Base\z/, /Record\z/].freeze

      def persistence?(node)
        superclass = ClassReading.superclass_of(node)
        return false if superclass.nil?

        BASES.any? { |pattern| pattern.match?(superclass) }
      end

      def models(sources)
        sources.select { |source| source.relative.start_with?("app/models/") }
      end
    end
  end
end
