# frozen_string_literal: true

require "shipshape/measures/finding"
require "shipshape/measures/naming"

module Shipshape
  module Measures
    # Controllers naming a constant that is a model.
    class RequestHandlingThatReachesPersistence
      TITLE = "Request handling reaching straight into persistence"
      LAW = "the-call-graph-is-declared"
      WHY = "Each of these is a place where a rule could live and does not, and where " \
            "changing the controller means understanding the schema."
      NOUN = "controllers"
      UNIT = :file

      def population(sources)
        controllers(sources).length
      end

      def exemplars(sources)
        models = model_names(sources)

        controllers(sources).reject { |source| touches?(source, models) }.map do |source|
          Finding.new(relative: source.relative, line: 1, label: "reaches no record at all")
        end
      end

      def call(sources)
        models = model_names(sources)

        controllers(sources).flat_map do |source|
          sends_in(source).select { |node| models.include?(node.receiver.source.split("::").last) }.map do |node|
            action = ClassReading.enclosing_method(source.ast, node)

            Finding.new(
              relative: source.relative,
              line: node.loc.line,
              label: "#{node.receiver.source}.#{node.method_name}",
              context: {
                action: action,
                subject: node.receiver.source.split("::").last,
                message: node.method_name,
              },
            )
          end
        end
      end

      def proposal(findings)
        finding = findings.find { |candidate| candidate.context && candidate.context[:action] }
        return nil if finding.nil?

        action = finding.context[:action]
        name = Naming.operation_for(action: action, subject: finding.context[:subject])
        kind = Naming.kind_for(action, message: finding.context[:message])

        <<~TEXT
          `#{finding.relative}:#{finding.line}` calls `#{finding.label}` inside `##{action}`.
          That belongs in an operation the action can call and a test can run without a
          controller:

          ```ruby
          # #{Naming.path_for(name, kind)}
          class #{name} < #{kind}
          #{constructor(action)}  def call
              # the #{finding.label} that is in the controller today
            end
          end
          ```

          The action then reads `@#{Naming.snake(finding.context[:subject])} = #{name}.call#{takes_id?(action) ? "(id: id)" : ""}` and decides nothing.
        TEXT
      end

      private

      def constructor(action)
        return "" unless takes_id?(action)

        "  def initialize(id:)\n      @id = typed(id, Integer)\n    end\n\n"
      end

      def takes_id?(action)
        %i[show edit update destroy].include?(action.to_sym)
      end

      def controllers(sources)
        sources.select { |source| source.relative.split("/")[1] == "controllers" }
      end

      # Only classes that are actually tables: counting the plain objects Rails put in
      # `app/models` would inflate this with the one thing a controller may do. The name comes
      # from the class declaration, so a namespaced class is matched as it is written.
      BASES = [/\AApplicationRecord\z/, /\AActiveRecord::Base\z/, /Record\z/].freeze

      def model_names(sources)
        sources.select { |source| source.relative.start_with?("app/models/") }.flat_map do |source|
          ClassReading.classes(source).select { |node| record?(node) }.map { |node| ClassReading.name_of(node) }
        end.to_set
      end

      def record?(node)
        superclass = ClassReading.superclass_of(node)
        return false if superclass.nil?

        BASES.any? { |pattern| pattern.match?(superclass) }
      end

      def touches?(source, models)
        sends_in(source).any? { |node| models.include?(node.receiver.source.split("::").last) }
      end

      def sends_in(source)
        found = []
        ClassReading.walk(source.ast) do |node|
          found << node if node.send_type? && node.receiver && node.receiver.const_type?
        end
        found
      end
    end
  end
end
