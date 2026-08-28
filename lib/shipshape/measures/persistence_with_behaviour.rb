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
      NOUN = "records"
      # Findings are sites, and many land in one file, so the clean count subtracts files.
      UNIT = :file

      def population(sources)
        records(sources).length
      end

      def exemplars(sources)
        records(sources).select { |_source, node| behaviour_of(node).empty? }.map do |source, node|
          Finding.new(relative: source.relative, line: node.loc.line,
                      label: "#{ClassReading.name_of(node)} — declarations only, no rules")
        end
      end

      def records(sources)
        models(sources).flat_map do |source|
          ClassReading.classes(source).select { |node| persistence?(node) }.map { |node| [source, node] }
        end
      end

      # Methods the framework asks a record to provide. They describe how the object is
      # addressed and rendered, not what the business does with it — and counting them both
      # inflates the number and picks a poor worked example. `Category#to_param` was the
      # first thing this report proposed extracting, which is not advice anybody wants.
      FRAMEWORK = %i[to_param to_partial_path to_key to_model to_s to_str persisted?
                     cache_key cache_key_with_version model_name].freeze

      def call(sources)
        models(sources).flat_map do |source|
          ClassReading.classes(source).select { |node| persistence?(node) }.flat_map do |node|
            behaviour_of(node).map do |method|
              Finding.new(
                relative: source.relative,
                line: method.loc.line,
                label: "##{method.method_name}",
                context: {
                  record: ClassReading.name_of(node),
                  method: method.method_name,
                  writes: Naming.writes?(method.body),
                  write: Naming.first_write_in(method.body),
                },
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
        # `settle!` must not become `Settle!Order`. Predicate and bang suffixes are Ruby
        # punctuation, not part of the name a class can carry.
        name = "#{Naming.camel(method.to_s.delete_suffix("?").delete_suffix("!"))}#{record}"
        kind = finding.context[:writes] ? "Command" : "Query"

        <<~TEXT
          `#{record}##{method}` is a rule living on the thing that stores it, reachable
          everywhere `#{record}` is — which is everywhere. Moved, it becomes callable by name
          and testable without a row:

          ```ruby
          # #{Naming.path_for(name, kind)}
          class #{name} < #{kind}
            def initialize(#{Naming.snake(record)}:)
              @#{Naming.snake(record)} = typed(#{Naming.snake(record)}, #{record})
            end

            def call
              # the body of #{record}##{method} today
            end
          end
          ```

          #{reasoning(finding, kind)}
        TEXT
      end

      private

      # The gem can see which it is, so it says so rather than handing the reader a
      # judgement it was perfectly able to make. Where a method writes, the write itself is
      # named — showing the evidence is what separates a measurement from an assertion.
      def reasoning(finding, kind)
        return "It calls `#{finding.context[:write]}`, so it writes: a Command." if finding.context[:writes]

        "Nothing in it writes, so it is a Query. A method that only derives a value from " \
          "what it was handed may not need a class at all — it may belong on the shape."
      end

      def behaviour_of(node)
        ClassReading.public_methods_of(node).reject { |method| FRAMEWORK.include?(method.method_name) }
      end

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
